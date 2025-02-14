// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IStrategy } from "src/tokemak/interfaces/strategy/IStrategy.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { StructuredLinkedList } from "src/tokemak/strategy/StructuredLinkedList.sol";
import { WithdrawalQueue } from "src/tokemak/strategy/WithdrawalQueue.sol";
import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { AutopoolToken } from "src/tokemak/vault/libs/AutopoolToken.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

library AutopoolDebt {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using WithdrawalQueue for StructuredLinkedList.List;
    using EnumerableSet for EnumerableSet.AddressSet;
    using AutopoolToken for AutopoolToken.TokenData;

    /// @notice Max time a cached debt report can be used
    uint256 public constant MAX_DEBT_REPORT_AGE_SECONDS = 1 days;

    error VaultShutdown();
    error WithdrawShareCalcInvalid(uint256 currentShares, uint256 cachedShares);
    error RebalanceDestinationsMatch(address destinationVault);
    error RebalanceFailed(string message);
    error InvalidPrices();
    error InvalidTotalAssetPurpose();
    error InvalidDestination(address destination);
    error TooFewAssets(uint256 requested, uint256 actual);
    error SharesAndAssetsReceived(uint256 assets, uint256 shares);
    error AmountExceedsAllowance(uint256 shares, uint256 allowed);
    error PositivePriceRecoupNotCovered(uint256 remaining);

    event DestinationDebtReporting(
        address destination, AutopoolDebt.IdleDebtUpdates debtInfo, uint256 claimed, uint256 claimGasUsed
    );
    event NewNavShareFeeMark(uint256 navPerShare, uint256 timestamp);
    event Nav(uint256 idle, uint256 debt, uint256 totalSupply);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    struct DestinationInfo {
        /// @notice Current underlying value at the destination vault
        /// @dev Used for calculating totalDebt, mid point of min and max
        uint256 cachedDebtValue;
        /// @notice Current minimum underlying value at the destination vault
        /// @dev Used for calculating totalDebt during withdrawal
        uint256 cachedMinDebtValue;
        /// @notice Current maximum underlying value at the destination vault
        /// @dev Used for calculating totalDebt of the deposit
        uint256 cachedMaxDebtValue;
        /// @notice Last block timestamp this info was updated
        uint256 lastReport;
        /// @notice How many shares of the destination vault we owned at last report
        uint256 ownedShares;
    }

    struct IdleDebtUpdates {
        bool pricesWereSafe;
        uint256 totalIdleDecrease;
        uint256 totalIdleIncrease;
        uint256 totalDebtIncrease;
        uint256 totalDebtDecrease;
        uint256 totalMinDebtIncrease;
        uint256 totalMinDebtDecrease;
        uint256 totalMaxDebtIncrease;
        uint256 totalMaxDebtDecrease;
    }

    struct RebalanceOutParams {
        /// Address that will received the withdrawn underlyer
        address receiver;
        /// The "out" destination vault
        address destinationOut;
        /// The amount of tokenOut that will be withdrawn
        uint256 amountOut;
        /// The underlyer for destinationOut
        address tokenOut;
        IERC20 _baseAsset;
        bool _shutdown;
    }

    /// @dev In memory struct only for managing vars in _withdraw
    struct WithdrawInfo {
        uint256 currentIdle;
        uint256 assetsFromIdle;
        uint256 totalAssetsToPull;
        uint256 assetsToPull;
        uint256 assetsPulled;
        uint256 idleIncrease;
        uint256 debtDecrease;
        uint256 debtMinDecrease;
        uint256 debtMaxDecrease;
        uint256 totalMinDebt;
        uint256 destinationRound;
        uint256 lastRoundSlippage;
        uint256 expectedAssets;
        uint256 remainingRecoup;
    }

    struct FlashRebalanceParams {
        uint256 totalIdle;
        uint256 totalDebt;
        IERC20 baseAsset;
        bool shutdown;
    }

    struct FlashResultInfo {
        uint256 tokenInBalanceBefore;
        uint256 tokenInBalanceAfter;
        bytes32 flashResult;
    }

    function flashRebalance(
        DestinationInfo storage destInfoOut,
        DestinationInfo storage destInfoIn,
        IERC3156FlashBorrower receiver,
        IStrategy.RebalanceParams memory params,
        IStrategy.SummaryStats memory destSummaryOut,
        IAutopoolStrategy autoPoolStrategy,
        FlashRebalanceParams memory flashParams,
        bytes calldata data
    ) external returns (IdleDebtUpdates memory result) {
        // Handle decrease (shares going "Out", cashing in shares and sending underlying back to swapper)
        // If the tokenOut is _asset we assume they are taking idle
        // which is already in the contract
        result = _handleRebalanceOut(
            AutopoolDebt.RebalanceOutParams({
                receiver: address(receiver),
                destinationOut: params.destinationOut,
                amountOut: params.amountOut,
                tokenOut: params.tokenOut,
                _baseAsset: flashParams.baseAsset,
                _shutdown: flashParams.shutdown
            }),
            destInfoOut
        );

        if (!result.pricesWereSafe) {
            revert InvalidPrices();
        }

        // Handle increase (shares coming "In", getting underlying from the swapper and trading for new shares)
        if (params.amountIn > 0) {
            FlashResultInfo memory flashResultInfo;
            // get "before" counts
            flashResultInfo.tokenInBalanceBefore = IERC20(params.tokenIn).balanceOf(address(this));

            // Give control back to the solver so they can make use of the "out" assets
            // and get our "in" asset
            flashResultInfo.flashResult = receiver.onFlashLoan(msg.sender, params.tokenIn, params.amountIn, 0, data);

            // We assume the solver will send us the assets
            flashResultInfo.tokenInBalanceAfter = IERC20(params.tokenIn).balanceOf(address(this));

            // Make sure the call was successful and verify we have at least the assets we think
            // we were getting
            if (
                flashResultInfo.flashResult != keccak256("ERC3156FlashBorrower.onFlashLoan")
                    || flashResultInfo.tokenInBalanceAfter < flashResultInfo.tokenInBalanceBefore + params.amountIn
            ) {
                revert Errors.FlashLoanFailed(params.tokenIn, params.amountIn);
            }

            {
                // make sure we have a valid path
                (bool success, string memory message) = autoPoolStrategy.verifyRebalance(params, destSummaryOut);
                if (!success) {
                    revert RebalanceFailed(message);
                }
            }

            if (params.tokenIn != address(flashParams.baseAsset)) {
                IdleDebtUpdates memory inDebtResult = _handleRebalanceIn(
                    destInfoIn,
                    IDestinationVault(params.destinationIn),
                    params.tokenIn,
                    flashResultInfo.tokenInBalanceAfter
                );
                if (!inDebtResult.pricesWereSafe) {
                    revert InvalidPrices();
                }
                result.totalDebtDecrease += inDebtResult.totalDebtDecrease;
                result.totalDebtIncrease += inDebtResult.totalDebtIncrease;
                result.totalMinDebtDecrease += inDebtResult.totalMinDebtDecrease;
                result.totalMinDebtIncrease += inDebtResult.totalMinDebtIncrease;
                result.totalMaxDebtDecrease += inDebtResult.totalMaxDebtDecrease;
                result.totalMaxDebtIncrease += inDebtResult.totalMaxDebtIncrease;
            } else {
                result.totalIdleIncrease += flashResultInfo.tokenInBalanceAfter - flashResultInfo.tokenInBalanceBefore;
            }
        }
    }

    /// @notice Perform deposit and debt info update for the "in" destination during a rebalance
    /// @dev This "in" function performs less validations than its "out" version
    /// @param dvIn The "in" destination vault
    /// @param tokenIn The underlyer for dvIn
    /// @param depositAmount The amount of tokenIn that will be deposited
    /// @return result Changes in debt values
    function _handleRebalanceIn(
        DestinationInfo storage destInfo,
        IDestinationVault dvIn,
        address tokenIn,
        uint256 depositAmount
    ) private returns (IdleDebtUpdates memory result) {
        LibAdapter._approve(IERC20(tokenIn), address(dvIn), depositAmount);

        // Snapshot our current shares so we know how much to back out
        uint256 originalShareBal = dvIn.balanceOf(address(this));

        // deposit to dv
        uint256 newShares = dvIn.depositUnderlying(depositAmount);

        // Update the debt info snapshot
        result = _recalculateDestInfo(destInfo, dvIn, originalShareBal, originalShareBal + newShares);
    }

    /**
     * @notice Perform withdraw and debt info update for the "out" destination during a rebalance
     * @dev This "out" function performs more validations and handles idle as opposed to "in" which does not
     *  debtDecrease The previous amount of debt destinationOut accounted for in totalDebt
     *  debtIncrease The current amount of debt destinationOut should account for in totalDebt
     *  idleDecrease Amount of baseAsset that was sent from the vault. > 0 only when tokenOut == baseAsset
     *  idleIncrease Amount of baseAsset that was claimed from Destination Vault
     * @param params Rebalance out params
     * @param destOutInfo The "out" destination vault info
     * @return assetChange debt and idle change data
     */
    function _handleRebalanceOut(
        RebalanceOutParams memory params,
        DestinationInfo storage destOutInfo
    ) private returns (IdleDebtUpdates memory assetChange) {
        // Handle decrease (shares going "Out", cashing in shares and sending underlying back to swapper)
        // If the tokenOut is _asset we assume they are taking idle
        // which is already in the contract
        if (params.amountOut > 0) {
            if (params.tokenOut != address(params._baseAsset)) {
                IDestinationVault dvOut = IDestinationVault(params.destinationOut);

                // Snapshot our current shares so we know how much to back out
                uint256 originalShareBal = dvOut.balanceOf(address(this));

                // Burning our shares will claim any pending baseAsset
                // rewards and send them to us.
                // Get our starting balance
                uint256 beforeBaseAssetBal = params._baseAsset.balanceOf(address(this));

                // Withdraw underlying from the destination vault
                // Shares are sent directly to the flashRebalance receiver
                // slither-disable-next-line unused-return
                dvOut.withdrawUnderlying(params.amountOut, params.receiver);

                // Update the debt info snapshot
                assetChange =
                    _recalculateDestInfo(destOutInfo, dvOut, originalShareBal, originalShareBal - params.amountOut);

                // Capture any rewards we may have claimed as part of withdrawing
                assetChange.totalIdleIncrease = params._baseAsset.balanceOf(address(this)) - beforeBaseAssetBal;
            } else {
                // If we are shutdown then the only operations we should be performing are those that get
                // the base asset back to the vault. We shouldn't be sending out more

                if (params._shutdown) {
                    revert VaultShutdown();
                }
                // Working with idle baseAsset which should be in the vault already
                // Just send it out
                IERC20(params.tokenOut).safeTransfer(params.receiver, params.amountOut);
                assetChange.totalIdleDecrease = params.amountOut;

                // We weren't dealing with any debt or pricing, just idle, so we can just mark
                // it as safe
                assetChange.pricesWereSafe = true;
            }
        }
    }

    function recalculateDestInfo(
        DestinationInfo storage destInfo,
        IDestinationVault destVault,
        uint256 originalShares,
        uint256 currentShares
    ) external returns (IdleDebtUpdates memory result) {
        result = _recalculateDestInfo(destInfo, destVault, originalShares, currentShares);
    }

    /// @dev Will not revert on unsafe prices. Up to the caller.
    function _recalculateDestInfo(
        DestinationInfo storage destInfo,
        IDestinationVault destVault,
        uint256 originalShares,
        uint256 currentShares
    ) private returns (IdleDebtUpdates memory result) {
        // Figure out what to back out of our totalDebt number.
        // We could have had withdraws since the last snapshot which means our
        // cached currentDebt number should be decreased based on the remaining shares
        // totalDebt is decreased using the same proportion of shares method during withdrawals
        // so this should represent whatever is remaining.

        // Prices are per LP token and whether or not the prices are safe to use
        // If they aren't safe then just continue and we'll get it on the next go around
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) = destVault.getRangePricesLP();

        // Calculate what we're backing out based on the original shares
        uint256 minPrice = spotPrice > safePrice ? safePrice : spotPrice;
        uint256 maxPrice = spotPrice > safePrice ? spotPrice : safePrice;

        // If we previously had shares, calculate how much of our cached numbers
        // still remain as this will be deducted from the overall debt numbers
        // over time
        uint256 prevOwnedShares = destInfo.ownedShares;
        if (prevOwnedShares > 0) {
            result.totalDebtDecrease = (destInfo.cachedDebtValue * originalShares) / prevOwnedShares;
            result.totalMinDebtDecrease = (destInfo.cachedMinDebtValue * originalShares) / prevOwnedShares;
            result.totalMaxDebtDecrease = (destInfo.cachedMaxDebtValue * originalShares) / prevOwnedShares;
        }

        // The overall debt value is the mid point of min and max
        uint256 div = 10 ** destVault.decimals();
        uint256 newDebtValue = (minPrice * currentShares + maxPrice * currentShares) / (div * 2);

        result.pricesWereSafe = isSpotSafe;
        result.totalDebtIncrease = newDebtValue;
        result.totalMinDebtIncrease = minPrice * currentShares / div;
        result.totalMaxDebtIncrease = maxPrice * currentShares / div;

        // Save our current new values
        destInfo.cachedDebtValue = newDebtValue;
        destInfo.cachedMinDebtValue = result.totalMinDebtIncrease;
        destInfo.cachedMaxDebtValue = result.totalMaxDebtIncrease;
        destInfo.lastReport = block.timestamp;
        destInfo.ownedShares = currentShares;
    }

    function totalAssetsTimeChecked(
        StructuredLinkedList.List storage debtReportQueue,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo,
        IAutopool.TotalAssetPurpose purpose
    ) external returns (uint256) {
        IDestinationVault destVault = IDestinationVault(debtReportQueue.peekHead());
        uint256 recalculatedTotalAssets = IAutopool(address(this)).totalAssets(purpose);

        while (address(destVault) != address(0)) {
            uint256 lastReport = destinationInfo[address(destVault)].lastReport;

            if (lastReport + MAX_DEBT_REPORT_AGE_SECONDS > block.timestamp) {
                // Its not stale

                // This report is OK, we don't need to recalculate anything
                break;
            } else {
                // It is stale, recalculate

                //slither-disable-next-line unused-return
                uint256 currentShares = destVault.balanceOf(address(this));
                uint256 staleDebt;
                uint256 extremePrice;

                // Figure out exactly which price to use based on its purpose
                if (purpose == IAutopool.TotalAssetPurpose.Deposit) {
                    // We use max value so that anything deposited is worth less
                    extremePrice = destVault.getUnderlyerCeilingPrice();

                    // Round down. We are subtracting this value out of the total so some left
                    // behind just increases the value which is what we want
                    staleDebt = destinationInfo[address(destVault)].cachedMaxDebtValue.mulDiv(
                        currentShares, destinationInfo[address(destVault)].ownedShares, Math.Rounding.Down
                    );
                } else if (purpose == IAutopool.TotalAssetPurpose.Withdraw) {
                    // We use min value so that we value the shares as worth less
                    extremePrice = destVault.getUnderlyerFloorPrice();
                    // Round up. We are subtracting this value out of the total so if we take a little
                    // extra it just decreases the value which is what we want
                    staleDebt = destinationInfo[address(destVault)].cachedMinDebtValue.mulDiv(
                        currentShares, destinationInfo[address(destVault)].ownedShares, Math.Rounding.Up
                    );
                } else {
                    revert InvalidTotalAssetPurpose();
                }

                // Back out our stale debt, add in its new value
                // Our goal is to find the most conservative value in each situation. If the current
                // value we have represents that, then use it. Otherwise, use the new one.
                uint256 newValue = (currentShares * extremePrice) / destVault.ONE();

                if (purpose == IAutopool.TotalAssetPurpose.Deposit && staleDebt > newValue) {
                    newValue = staleDebt;
                } else if (purpose == IAutopool.TotalAssetPurpose.Withdraw && staleDebt < newValue) {
                    newValue = staleDebt;
                }

                recalculatedTotalAssets = recalculatedTotalAssets + newValue - staleDebt;
            }

            destVault = IDestinationVault(debtReportQueue.getAdjacent(address(destVault), true));
        }

        return recalculatedTotalAssets;
    }

    function _updateDebtReporting(
        StructuredLinkedList.List storage debtReportQueue,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo,
        uint256 numToProcess
    ) external returns (IdleDebtUpdates memory result) {
        numToProcess = Math.min(numToProcess, debtReportQueue.sizeOf());

        for (uint256 i = 0; i < numToProcess; ++i) {
            IDestinationVault destVault = IDestinationVault(debtReportQueue.popHead());

            // Get the reward value we've earned. DV rewards are always in terms of base asset
            // We track the gas used purely for off-chain stats purposes
            // Main rewarder on DV's store the earned and liquidated rewards
            // Extra rewarders are disabled at the DV level
            uint256 claimGasUsed = gasleft();
            uint256 beforeBaseAsset = IERC20(IAutopool(address(this)).asset()).balanceOf(address(this));
            IMainRewarder(destVault.rewarder()).getReward(address(this), address(this), false);
            uint256 claimedRewardValue =
                IERC20(IAutopool(address(this)).asset()).balanceOf(address(this)) - beforeBaseAsset;
            result.totalIdleIncrease += claimedRewardValue;

            // Recalculate the debt info figuring out the change in
            // total debt value we can roll up later
            uint256 currentShareBalance = destVault.balanceOf(address(this));

            AutopoolDebt.IdleDebtUpdates memory debtResult = _recalculateDestInfo(
                destinationInfo[address(destVault)], destVault, currentShareBalance, currentShareBalance
            );

            result.totalDebtDecrease += debtResult.totalDebtDecrease;
            result.totalDebtIncrease += debtResult.totalDebtIncrease;
            result.totalMinDebtDecrease += debtResult.totalMinDebtDecrease;
            result.totalMinDebtIncrease += debtResult.totalMinDebtIncrease;
            result.totalMaxDebtDecrease += debtResult.totalMaxDebtDecrease;
            result.totalMaxDebtIncrease += debtResult.totalMaxDebtIncrease;

            // If we no longer have shares, then there's no reason to continue reporting on the destination.
            // The strategy will only call for the info if its moving "out" of the destination
            // and that will only happen if we have shares.
            // A rebalance where we move "in" to the position will refresh the data at that time
            if (currentShareBalance > 0) {
                debtReportQueue.addToTail(address(destVault));
            }

            claimGasUsed -= gasleft();

            emit DestinationDebtReporting(address(destVault), debtResult, claimedRewardValue, claimGasUsed);
        }
    }

    function _initiateWithdrawInfo(
        uint256 assets,
        IAutopool.AssetBreakdown storage assetBreakdown
    ) private view returns (WithdrawInfo memory) {
        uint256 idle = assetBreakdown.totalIdle;
        WithdrawInfo memory info = WithdrawInfo({
            currentIdle: idle,
            // If idle can cover the full amount, then we want to pull all assets from there
            // Otherwise, we want to pull from the market and only get idle if we exhaust the market
            assetsFromIdle: assets > idle ? 0 : assets,
            totalAssetsToPull: 0,
            assetsToPull: 0,
            assetsPulled: 0,
            idleIncrease: 0,
            debtDecrease: 0,
            debtMinDecrease: 0,
            debtMaxDecrease: 0,
            totalMinDebt: assetBreakdown.totalDebtMin,
            destinationRound: 0,
            lastRoundSlippage: 0,
            expectedAssets: 0,
            remainingRecoup: 0
        });

        info.totalAssetsToPull = assets - info.assetsFromIdle;

        // This var we use to track our progress later
        info.assetsToPull = assets - info.assetsFromIdle;

        // Idle + minDebt is the maximum amount of assets/debt we could burn during a withdraw.
        // If the user is request more than that (like during a withdraw) we can just revert
        // early without trying
        if (info.totalAssetsToPull > info.currentIdle + info.totalMinDebt) {
            revert TooFewAssets(assets, info.currentIdle + info.totalMinDebt);
        }

        return info;
    }

    function withdraw(
        uint256 assets,
        uint256 applicableTotalAssets,
        IAutopool.AssetBreakdown storage assetBreakdown,
        StructuredLinkedList.List storage withdrawalQueue,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo
    ) public returns (uint256 actualAssets, uint256 actualShares, uint256 debtBurned) {
        WithdrawInfo memory info = _initiateWithdrawInfo(assets, assetBreakdown);

        // Pull the market if there aren't enough funds in idle to cover the entire amount

        // This flow is not bounded by a set number of shares. The user has requested X assets
        // and a variable number of shares to burn so we don't have easy break out points like we do
        // during redeem (like using debt burned). When we get slippage here and don't meet the requested assets
        // we need to keep going if we can. This is tricky if we consider that (most of) our destinations are
        // LP positions and we'll be swapping assets, so we can expect some slippage. Even
        // if our minDebtValue numbers are up to date and perfectly accurate slippage could ensure we
        // are always receiving less than we expect/calculate and we never hit the requested assets
        // even though the owner would have shares to cover it. Under normal/expected conditions, our
        // minDebtValue is lower than actual and we expect overall value to be going up, so we burn a tad
        // more than we should and receive a tad more than we expect. This should cover us. However,
        // in other conditions we have to be sure we aren't endlessly trying to approach 0 so we are tracking
        // the slippage we received on the last pull, repricing, and applying an increasing multiplier until we either
        // pull enough to cover or pull them all and/or move to the next destination.

        uint256 dvSharesToBurn;
        while (info.assetsToPull > 0) {
            IDestinationVault destVault = IDestinationVault(withdrawalQueue.peekHead());

            // We've run out of destinations
            if (address(destVault) == address(0)) {
                break;
            }

            uint256 dvShares = destVault.balanceOf(address(this));
            {
                uint256 dvSharesValue;
                if (info.destinationRound == 0) {
                    // First time pulling

                    // We use the min debt value here because its a withdrawal and we're trying to cover an amount
                    // of assets. Undervaluing the shares may mean we pull more but given that we expect slippage
                    // that is desirable.
                    dvSharesValue = destinationInfo[address(destVault)].cachedMinDebtValue * dvShares
                        / destinationInfo[address(destVault)].ownedShares;
                } else {
                    // When we've pulled from this destination before, i.e. destinationRound > 0, then we
                    // know a more accurate exchange rate and its worse than we were expecting.
                    // We even will pad it a bit as we want to account for any additional slippage we
                    // may receive by say being farther down an AMM curve.

                    // dvSharesToBurn is the last value we used when pulling from this destination
                    // info.expectedAssets is how much we expected to get on that last pull
                    // info.expectedAssets - info.lastRoundSlippage is how much we actually received

                    uint256 paddedSlippage = info.lastRoundSlippage * (info.destinationRound + 10_000) / 10_000;

                    if (paddedSlippage < info.expectedAssets) {
                        dvSharesValue = (info.expectedAssets - paddedSlippage) * dvShares / dvSharesToBurn;
                    } else {
                        // This will just mean we pull all shares
                        dvSharesValue = 0;
                    }
                }

                if (dvSharesValue > info.assetsToPull) {
                    dvSharesToBurn = (dvShares * info.assetsToPull) / dvSharesValue;

                    // On withdraw, we are trying to meet a specific number of assets without a limit
                    // on the debt we can burn. Burning 0 due to the valuations here would be an automatic failure
                    // as we still have assets to satisfy and debt to burn. We at least have to burn 1 even if it
                    // results in a larger over pull
                    if (dvSharesToBurn == 0) {
                        dvSharesToBurn = 1;
                    }

                    // Only need to set it here because the only time we'll use it is if
                    // we don't exhaust all shares and have to try the destination again
                    info.expectedAssets = info.assetsToPull;
                } else {
                    dvSharesToBurn = dvShares;
                }
            }

            uint256 pulledAssets;
            uint256 debtValueBurned;
            // Get the base asset back from the Destination. Also performs a check that we aren't receiving
            // poor execution on our swaps based on safe prices
            (info, pulledAssets, debtValueBurned) = _withdrawAssets(info, destinationInfo, destVault, dvSharesToBurn);

            info.assetsPulled += pulledAssets;

            if (info.remainingRecoup > 0) {
                // If the destination is so severely undervalued that it can't cover its own recoup then we have no
                // recourse but to burn the entire destination and the user would to have to cover the full overage
                // from the next destinations can get nothing from this one. Should not be allowed.
                revert PositivePriceRecoupNotCovered(info.remainingRecoup);
            }

            // If we've exhausted all shares we can remove the withdrawal from the queue
            // We need to leave it in the debt report queue though so that our destination specific
            // debt tracking values can be updated
            if (dvShares == dvSharesToBurn) {
                withdrawalQueue.popAddress(address(destVault));
                info.destinationRound = 0;
                info.lastRoundSlippage = 0;
            } else {
                // If we didn't burn all the shares and we received enough to cover our
                // expected that means we'll break out below as we've hit our target
                unchecked {
                    if (pulledAssets < info.expectedAssets) {
                        info.lastRoundSlippage = info.expectedAssets - pulledAssets;
                        if (info.destinationRound == 0) {
                            info.destinationRound = 100;
                        } else {
                            info.destinationRound *= 2;
                        }
                    }
                }
            }

            // It's possible we'll get back more assets than we anticipate from a swap
            // so if we do, throw it in idle and stop processing. You don't get more than we've calculated
            if (info.assetsPulled >= info.totalAssetsToPull) {
                info.idleIncrease += info.assetsPulled - info.totalAssetsToPull;
                info.assetsPulled = info.totalAssetsToPull;
                info.assetsToPull = 0;
                break;
            }

            info.assetsToPull -= pulledAssets;
        }

        // We didn't get enough assets from the debt pull
        // See if we can get the rest from idle
        if (info.assetsPulled < assets && info.currentIdle > 0) {
            uint256 remaining = assets - info.assetsPulled;
            if (remaining <= info.currentIdle) {
                info.assetsFromIdle = remaining;
            }
            // We don't worry about the else case because if currentIdle can't
            // cover remaining then we'll fail the `actualAssets < assets`
            // check below and revert
        }

        debtBurned = info.assetsFromIdle + info.debtMinDecrease;
        actualAssets = info.assetsFromIdle + info.assetsPulled;

        if (actualAssets < assets) {
            revert TooFewAssets(assets, actualAssets);
        }

        actualShares = IAutopool(address(this)).convertToShares(
            Math.max(actualAssets, debtBurned),
            applicableTotalAssets,
            IAutopool(address(this)).totalSupply(),
            Math.Rounding.Up
        );

        // Subtract what's taken out of idle from totalIdle
        // We may also have some increase to account for it we over pulled
        // or received better execution than we were anticipating
        // slither-disable-next-line events-maths
        assetBreakdown.totalIdle = info.currentIdle + info.idleIncrease - info.assetsFromIdle;

        // Save off our various debt numbers
        if (info.debtDecrease > assetBreakdown.totalDebt) {
            assetBreakdown.totalDebt = 0;
        } else {
            assetBreakdown.totalDebt -= info.debtDecrease;
        }

        if (info.debtMinDecrease > info.totalMinDebt) {
            assetBreakdown.totalDebtMin = 0;
        } else {
            assetBreakdown.totalDebtMin -= info.debtMinDecrease;
        }

        if (info.debtMaxDecrease > assetBreakdown.totalDebtMax) {
            assetBreakdown.totalDebtMax = 0;
        } else {
            assetBreakdown.totalDebtMax -= info.debtMaxDecrease;
        }
    }

    function _withdrawAssets(
        WithdrawInfo memory info,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo,
        IDestinationVault destVault,
        uint256 dvSharesToBurn
    ) internal returns (WithdrawInfo memory, uint256 pulledAssets, uint256 debtValueBurned) {
        if (dvSharesToBurn > 0) {
            address[] memory tokensBurned;
            uint256[] memory amountsBurned;

            // Destination Vaults always burn the exact amount we instruct them to
            (pulledAssets, tokensBurned, amountsBurned) = destVault.withdrawBaseAsset(dvSharesToBurn, address(this));

            // Calculate the totalDebt we'll need to remove based on the shares we're burning
            // We're rounding up here so take care when actually applying to totalDebt
            debtValueBurned = destinationInfo[address(destVault)].cachedMinDebtValue.mulDiv(
                dvSharesToBurn, destinationInfo[address(destVault)].ownedShares, Math.Rounding.Up
            );
            info.debtMinDecrease += debtValueBurned;

            info.debtDecrease += destinationInfo[address(destVault)].cachedDebtValue.mulDiv(
                dvSharesToBurn, destinationInfo[address(destVault)].ownedShares, Math.Rounding.Up
            );

            uint256 maxDebtBurned = destinationInfo[address(destVault)].cachedMaxDebtValue.mulDiv(
                dvSharesToBurn, destinationInfo[address(destVault)].ownedShares, Math.Rounding.Up
            );
            info.debtMaxDecrease += maxDebtBurned;

            // See if we received a reasonable amount of the base asset back based on the value
            // of the tokens that were burned.
            uint256 totalValueBurned;
            {
                uint256 tokenLen = tokensBurned.length;
                IRootPriceOracle rootPriceOracle = ISystemRegistry(destVault.getSystemRegistry()).rootPriceOracle();
                for (uint256 i = 0; i < tokenLen;) {
                    totalValueBurned += amountsBurned[i] * rootPriceOracle.getPriceInEth(tokensBurned[i])
                        / (10 ** IERC20(tokensBurned[i]).decimals());
                    unchecked {
                        ++i;
                    }
                }
            }

            // How much, if any, should be dropping into idle?
            // Anything pulled over debtValueBurned goes to idle, user can't get more than we think its worth.
            // However, if we pulled less than the current value of the tokens we burned, so long as
            // that value is greater than debt min, we need to recoup that as well and put it into idle

            uint256 amountToRecoup;
            if (totalValueBurned > debtValueBurned) {
                // The shares we burned are worth more than we'll be recouping from the debt burn
                // the difference we still need to get
                amountToRecoup = totalValueBurned - debtValueBurned;

                uint256 maxCreditBps = destVault.recoupMaxCredit();
                uint256 gapCredit = maxDebtBurned - debtValueBurned;
                uint256 credit = Math.min(gapCredit, debtValueBurned * maxCreditBps / 10_000);

                if (credit > amountToRecoup) {
                    amountToRecoup = 0;
                } else {
                    amountToRecoup -= credit;
                }
            }

            // This is done regardless of whether we were under valued. User can still only
            // get what we've valued it at.
            if (pulledAssets > debtValueBurned) {
                uint256 overDebtValue = pulledAssets - debtValueBurned;
                info.idleIncrease += overDebtValue;
                pulledAssets -= overDebtValue;

                // Since this is going to idle it goes to satisfy the recoup as well
                if (amountToRecoup > 0) {
                    if (amountToRecoup > overDebtValue) {
                        amountToRecoup -= overDebtValue;
                    } else {
                        amountToRecoup = 0;
                    }
                }
            }

            // If we still have a value we need to recoup it means that the debt range credit
            // as well as what was pulled over the min debt value wasn't enough to cover
            // the under valued burn. Now we have to try and take it from what is going back
            // to the user
            if (amountToRecoup > 0) {
                if (amountToRecoup > pulledAssets) {
                    // Recoup is more than we pulled so we'll have some recoup left over
                    amountToRecoup -= pulledAssets;

                    // Everything that was pulled goes to idle
                    info.idleIncrease += pulledAssets;
                    pulledAssets = 0;

                    // We'll have to try and get the remaining amount from another destination
                    info.remainingRecoup += amountToRecoup;
                } else {
                    // We pulled enough assets to cover the recoup
                    pulledAssets -= amountToRecoup;

                    // Ensure the recoup goes to idle
                    info.idleIncrease += amountToRecoup;
                }
            }
        }

        return (info, pulledAssets, debtValueBurned);
    }

    /// @notice Perform a removal of assets via the redeem path where the shares are the limiting factor.
    /// This means we break out whenever we reach either `assets` retrieved or debt value equivalent to `assets` burned
    function redeem(
        uint256 assets,
        uint256 applicableTotalAssets,
        IAutopool.AssetBreakdown storage assetBreakdown,
        StructuredLinkedList.List storage withdrawalQueue,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo
    ) public returns (uint256 actualAssets, uint256 actualShares, uint256 debtBurned) {
        WithdrawInfo memory info = _initiateWithdrawInfo(assets, assetBreakdown);

        // If not enough funds in idle, then pull what we need from destinations
        bool exhaustedDestinations = false;
        while (info.assetsToPull > 0) {
            IDestinationVault destVault = IDestinationVault(withdrawalQueue.peekHead());
            if (address(destVault) == address(0)) {
                exhaustedDestinations = true;
                break;
            }

            uint256 dvShares = destVault.balanceOf(address(this));
            uint256 dvSharesToBurn = dvShares;
            {
                // Valuing these shares higher, rounding up, will result in us burning less of them
                // in the event we don't burn all of them. Good thing.
                uint256 dvSharesValue = destinationInfo[address(destVault)].cachedMinDebtValue.mulDiv(
                    dvSharesToBurn, destinationInfo[address(destVault)].ownedShares, Math.Rounding.Up
                );

                // If the dv shares we own are worth more than we need, limit the shares to burn
                // Any extra we get will be dropped into idle
                if (dvSharesValue > info.assetsToPull) {
                    uint256 limitedShares = (dvSharesToBurn * info.assetsToPull) / dvSharesValue;

                    // Final set for the actual shares we'll burn later
                    dvSharesToBurn = limitedShares;
                }
            }

            uint256 pulledAssets;
            uint256 debtValueBurned;
            // Get the base asset back from the Destination. Also performs a check that we aren't receiving
            // poor execution on our swaps based on safe prices
            // slither-disable-next-line unused-return
            (info, pulledAssets, debtValueBurned) = _withdrawAssets(info, destinationInfo, destVault, dvSharesToBurn);

            // If we've exhausted all shares we can remove the destination from the withdrawal queue
            // We need to leave it in the debt report queue though so that our destination specific
            // debt tracking values can be updated
            if (dvShares == dvSharesToBurn) {
                withdrawalQueue.popAddress(address(destVault));
            }

            info.assetsPulled += pulledAssets;

            // Any deficiency in the amount we received is slippage.
            // There is a round up on debtValueBurned so just making sure it never under flows here
            // _withdrawAssets ensures that pulledAssets is always lte debtValueBurned and we always
            // want to debit the max so we just use debtValueBurned
            if (debtValueBurned > info.assetsToPull) {
                info.assetsToPull = 0;
            } else {
                info.assetsToPull -= debtValueBurned;
            }

            // We either have enough assets, or we've burned the max debt we're allowed
            if (info.assetsToPull == 0) {
                break;
            }

            // If we didn't exhaust all of the shares from the destination it means we
            // assume we will get everything we need from there and everything else is slippage
            if (dvShares != dvSharesToBurn) {
                info.assetsToPull = 0;
                break;
            }
        }

        // See if we can pull the remaining recoup from other destinations we may have pulled from
        if (info.remainingRecoup > 0) {
            if (info.remainingRecoup > info.assetsPulled) {
                info.remainingRecoup -= info.assetsPulled;
                info.idleIncrease += info.assetsPulled;
                info.assetsPulled = 0;
            } else {
                info.assetsPulled -= info.remainingRecoup;
                info.idleIncrease += info.remainingRecoup;
                info.remainingRecoup = 0;
            }
        }

        // We didn't get enough assets from the debt pull
        // See if we can get the rest from idle
        if (info.assetsToPull > 0 && info.currentIdle > 0 && exhaustedDestinations) {
            if (info.assetsToPull < info.currentIdle) {
                info.assetsFromIdle = info.assetsToPull;
            } else {
                info.assetsFromIdle = info.currentIdle;
            }
        }

        debtBurned = info.assetsFromIdle + info.debtMinDecrease;
        actualAssets = info.assetsFromIdle + info.assetsPulled;

        // If we took from idle, and we have remaining assets to recoup
        // we need to put some back in idle
        if (info.remainingRecoup > 0 && info.assetsFromIdle > 0) {
            // We only need to do this if the idle assets can cover the remaining recoup fully because
            // we'll be reverting otherwise
            if (info.assetsFromIdle >= info.remainingRecoup) {
                // We still need to charge for the recoup so we're going to leave it in debtBurned
                // but we'll take it back out of actualAssets so it stays in idle. We need to lower
                // assetsFromIdle as well so that the final numbers get updated too
                actualAssets -= info.remainingRecoup;
                info.assetsFromIdle -= info.remainingRecoup;
                info.remainingRecoup = 0;
            } else {
                // Just updating this number so we get an accurate value in the revert below
                info.remainingRecoup -= info.assetsFromIdle;
            }
        }

        // We took everything we could and still can't cover, time to revert
        if (info.remainingRecoup > 0) {
            revert PositivePriceRecoupNotCovered(info.remainingRecoup);
        }

        actualShares = IAutopool(address(this)).convertToShares(
            debtBurned, applicableTotalAssets, IAutopool(address(this)).totalSupply(), Math.Rounding.Up
        );

        // Subtract what's taken out of idle from totalIdle
        // We may also have some increase to account for it we over pulled
        // or received better execution than we were anticipating
        // slither-disable-next-line events-maths
        assetBreakdown.totalIdle = info.currentIdle + info.idleIncrease - info.assetsFromIdle;

        // Save off our various debt numbers
        if (info.debtDecrease > assetBreakdown.totalDebt) {
            assetBreakdown.totalDebt = 0;
        } else {
            assetBreakdown.totalDebt -= info.debtDecrease;
        }

        if (info.debtMinDecrease > info.totalMinDebt) {
            assetBreakdown.totalDebtMin = 0;
        } else {
            assetBreakdown.totalDebtMin -= info.debtMinDecrease;
        }

        if (info.debtMaxDecrease > assetBreakdown.totalDebtMax) {
            assetBreakdown.totalDebtMax = 0;
        } else {
            assetBreakdown.totalDebtMax -= info.debtMaxDecrease;
        }
    }

    /**
     * @notice Function to complete a withdrawal or redeem.  This runs after shares to be burned and assets to be
     *    transferred are calculated.
     * @param assets Amount of assets to be transferred to receiver.
     * @param shares Amount of shares to be burned from owner.
     * @param owner Owner of shares, user to burn shares from.
     * @param receiver The receiver of the baseAsset.
     * @param baseAsset Base asset of the Autopool.
     * @param assetBreakdown Asset breakdown for the Autopool.
     * @param tokenData Token data for the Autopool.
     */
    function completeWithdrawal(
        uint256 assets,
        uint256 shares,
        address owner,
        address receiver,
        IERC20 baseAsset,
        IAutopool.AssetBreakdown storage assetBreakdown,
        AutopoolToken.TokenData storage tokenData
    ) external {
        if (msg.sender != owner) {
            uint256 allowed = IAutopool(address(this)).allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                if (shares > allowed) revert AmountExceedsAllowance(shares, allowed);

                unchecked {
                    tokenData.approve(owner, msg.sender, allowed - shares);
                }
            }
        }

        tokenData.burn(owner, shares);

        uint256 ts = IAutopool(address(this)).totalSupply();

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        emit Nav(assetBreakdown.totalIdle, assetBreakdown.totalDebt, ts);

        baseAsset.safeTransfer(receiver, assets);
    }

    /**
     * @notice A helper function to get estimates of what would happen on a withdraw or redeem.
     * @dev Reverts all changing state.
     * @param previewWithdraw Bool denoting whether to preview a redeem or withdrawal.
     * @param assets Assets to be withdrawn or redeemed.
     * @param applicableTotalAssets Operation dependent assets in the Autopool.
     * @param functionCallEncoded Abi encoded function signature for recursive call.
     * @param assetBreakdown Breakdown of vault assets from Autopool storage.
     * @param withdrawalQueue Destination vault withdrawal queue from Autopool storage.
     * @param destinationInfo Mapping of information for destinations.
     * @return assetsAmount Preview of amount of assets to send to receiver.
     * @return sharesAmount Preview of amount of assets to burn from owner.
     */
    function preview(
        bool previewWithdraw,
        uint256 assets,
        uint256 applicableTotalAssets,
        bytes memory functionCallEncoded,
        IAutopool.AssetBreakdown storage assetBreakdown,
        StructuredLinkedList.List storage withdrawalQueue,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo
    ) external returns (uint256 assetsAmount, uint256 sharesAmount) {
        if (msg.sender != address(this)) {
            // Perform a recursive call the function in `funcCallEncoded`.  This will result in a call back to
            // the Autopool, and then this function. The intention is to reach the "else" block in this function.
            // solhint-disable avoid-low-level-calls
            // slither-disable-next-line missing-zero-check,low-level-calls
            (bool success, bytes memory returnData) = address(this).call(functionCallEncoded);
            // solhint-enable avoid-low-level-calls

            // If the recursive call is successful, it means an unintended code path was taken.
            if (success) {
                revert Errors.UnreachableError();
            }

            bytes4 sharesAmountSig = bytes4(keccak256("SharesAndAssetsReceived(uint256,uint256)"));

            // Extract the error signature (first 4 bytes) from the revert reason.
            bytes4 errorSignature;
            // solhint-disable no-inline-assembly
            assembly {
                errorSignature := mload(add(returnData, 0x20))
            }

            // If the error matches the expected signature, extract the amount from the revert reason and return.
            if (errorSignature == sharesAmountSig) {
                // Extract subsequent bytes for uint256.
                assembly {
                    assetsAmount := mload(add(returnData, 0x24))
                    sharesAmount := mload(add(returnData, 0x44))
                }
            } else {
                // If the error is not the expected one, forward the original revert reason.
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
            // solhint-enable no-inline-assembly
        }
        // This branch is taken during the recursive call.
        else {
            // Perform the actual withdrawal or redeem logic to compute the amount. This will be reverted to
            // simulate the action.
            uint256 previewAssets;
            uint256 previewShares;
            if (previewWithdraw) {
                (previewAssets, previewShares,) =
                    withdraw(assets, applicableTotalAssets, assetBreakdown, withdrawalQueue, destinationInfo);
            } else {
                (previewAssets, previewShares,) =
                    redeem(assets, applicableTotalAssets, assetBreakdown, withdrawalQueue, destinationInfo);
            }

            // Revert with the computed amount as an error.
            revert SharesAndAssetsReceived(previewAssets, previewShares);
        }
    }
}
