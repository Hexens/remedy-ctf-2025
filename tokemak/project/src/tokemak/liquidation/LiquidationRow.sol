// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SwapParams } from "src/tokemak/interfaces/liquidation/IAsyncSwapper.sol";
import { ILiquidationRow } from "src/tokemak/interfaces/liquidation/ILiquidationRow.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IDestinationVaultRegistry } from "src/tokemak/interfaces/vault/IDestinationVaultRegistry.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { IAsyncSwapper } from "src/tokemak/interfaces/liquidation/IAsyncSwapper.sol";

contract LiquidationRow is ILiquidationRow, ReentrancyGuard, SystemComponent, SecurityBase {
    using Address for address;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice An instance of the DestinationVaultRegistry contract.
    IDestinationVaultRegistry internal immutable destinationVaultRegistry;

    EnumerableSet.AddressSet private rewardTokens;

    /// @notice Whitelisted swapper for liquidating vaults for token
    EnumerableSet.AddressSet private whitelistedSwappers;

    /// @notice Mapping to store the balance amount for each vault for each token
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice Mapping to store the total balance for each token
    mapping(address => uint256) private totalTokenBalances;

    /// @notice Mapping to store the list of vaults for each token
    mapping(address => EnumerableSet.AddressSet) private tokenVaults;

    /// @notice Fee in basis points (bps). 1 bps is 0.01%
    uint256 public feeBps = 0;

    /// @notice Margin in basis points (bps). Used to calculate the price margin for the swap
    uint256 public priceMarginBps = 0;

    /// @notice Address to receive the fees
    address public feeReceiver;

    uint256 public constant MAX_PCT = 10_000;

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        destinationVaultRegistry = _systemRegistry.destinationVaultRegistry();

        // System registry must be properly initialized first
        Errors.verifyNotZero(address(destinationVaultRegistry), "destinationVaultRegistry");

        _setPriceMarginBps(200);
    }

    /// @notice Restricts access to whitelisted swappers
    modifier onlyWhitelistedSwapper(
        address swapper
    ) {
        if (!whitelistedSwappers.contains(swapper)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    /// @inheritdoc ILiquidationRow
    function addToWhitelist(
        address swapper
    ) external hasRole(Roles.REWARD_LIQUIDATION_MANAGER) {
        Errors.verifyNotZero(swapper, "swapper");
        if (!whitelistedSwappers.add(swapper)) revert Errors.ItemExists();
        emit SwapperAdded(swapper);
    }

    /// @inheritdoc ILiquidationRow
    function removeFromWhitelist(
        address swapper
    ) external hasRole(Roles.REWARD_LIQUIDATION_MANAGER) {
        if (!whitelistedSwappers.remove(swapper)) revert Errors.ItemNotFound();
        emit SwapperRemoved(swapper);
    }

    /// @inheritdoc ILiquidationRow
    function isWhitelisted(
        address swapper
    ) external view returns (bool) {
        return whitelistedSwappers.contains(swapper);
    }

    /// @inheritdoc ILiquidationRow
    function setFeeAndReceiver(
        address _feeReceiver,
        uint256 _feeBps
    ) external hasRole(Roles.REWARD_LIQUIDATION_MANAGER) {
        // _feeBps should be less than or equal to 50%. Want to limit the amount of received that can be taken as fee.
        if (_feeBps > MAX_PCT / 2) revert FeeTooHigh();

        feeBps = _feeBps;
        // slither-disable-next-line missing-zero-check
        feeReceiver = _feeReceiver;

        emit FeeReceiverSet(_feeReceiver, _feeBps);
    }

    /// @inheritdoc ILiquidationRow
    function setPriceMarginBps(
        uint256 _priceMarginBps
    ) external hasRole(Roles.REWARD_LIQUIDATION_MANAGER) {
        _setPriceMarginBps(_priceMarginBps);
    }

    function calculateFee(
        uint256 amount
    ) public view returns (uint256) {
        return (amount * feeBps) / MAX_PCT;
    }

    /// @inheritdoc ILiquidationRow
    function claimsVaultRewards(
        IDestinationVault[] memory vaults
    ) external nonReentrant hasRole(Roles.REWARD_LIQUIDATION_EXECUTOR) {
        if (vaults.length == 0) revert Errors.InvalidParam("vaults");

        for (uint256 i = 0; i < vaults.length; ++i) {
            uint256 gasBefore = gasleft();
            IDestinationVault vault = vaults[i];

            destinationVaultRegistry.verifyIsRegistered(address(vault));

            (uint256[] memory amounts, address[] memory tokens) = vault.collectRewards();

            uint256 tokensLength = tokens.length;
            for (uint256 j = 0; j < tokensLength; ++j) {
                address token = tokens[j];
                uint256 amount = amounts[j];
                if (amount > 0 && token != address(0)) {
                    // slither-disable-next-line reentrancy-no-eth
                    _increaseBalance(address(token), address(vault), amount);
                }
            }
            uint256 gasUsed = gasBefore - gasleft();
            emit GasUsedForVault(address(vault), gasUsed, bytes32("claim"));
        }
    }

    /// @inheritdoc ILiquidationRow
    function balanceOf(address tokenAddress, address vaultAddress) external view returns (uint256) {
        return balances[tokenAddress][vaultAddress];
    }

    /// @inheritdoc ILiquidationRow
    function totalBalanceOf(
        address tokenAddress
    ) external view returns (uint256) {
        return totalTokenBalances[tokenAddress];
    }

    /// @inheritdoc ILiquidationRow
    function getTokens() external view returns (address[] memory) {
        return rewardTokens.values();
    }

    /// @inheritdoc ILiquidationRow
    function getVaultsForToken(
        address tokenAddress
    ) external view returns (address[] memory) {
        return tokenVaults[tokenAddress].values();
    }

    /// @inheritdoc ILiquidationRow
    function liquidateVaultsForTokens(
        LiquidationParams[] memory liquidationParams
    ) external nonReentrant hasRole(Roles.REWARD_LIQUIDATION_EXECUTOR) {
        uint256 len = liquidationParams.length;
        Errors.verifyNotZero(len, "len");
        for (uint256 i = 0; i < len;) {
            _liquidateVaultsForToken(
                liquidationParams[i].fromToken,
                liquidationParams[i].asyncSwapper,
                liquidationParams[i].vaultsToLiquidate,
                liquidationParams[i].param
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc ILiquidationRow
    function liquidateVaultsForToken(
        LiquidationParams memory liquidationParams
    ) external nonReentrant hasRole(Roles.REWARD_LIQUIDATION_EXECUTOR) {
        _liquidateVaultsForToken(
            liquidationParams.fromToken,
            liquidationParams.asyncSwapper,
            liquidationParams.vaultsToLiquidate,
            liquidationParams.param
        );
    }

    /**
     * @notice Conducts the liquidation process for a specific token across a list of vaults,
     * performing the necessary balance adjustments, initiating the swap process via the asyncSwapper,
     * taking a fee from the received amount, and queues the remaining swapped tokens in the MainRewarder associated
     * with
     * each vault.
     * @dev This function calls the _prepareForLiquidation and _performLiquidation functions. These helper functions
     * were created to avoid a "stack too deep" error. These functions should only be used within the context of this
     * function.
     * @param fromToken The token that needs to be liquidated
     * @param asyncSwapper The address of the async swapper contract
     * @param vaultsToLiquidate The list of vaults that need to be liquidated
     * @param params Parameters for the async swap
     */
    function _liquidateVaultsForToken(
        address fromToken,
        address asyncSwapper,
        IDestinationVault[] memory vaultsToLiquidate,
        SwapParams memory params
    ) private onlyWhitelistedSwapper(asyncSwapper) {
        uint256 gasBefore = gasleft();

        (uint256 totalBalanceToLiquidate, uint256[] memory vaultsBalances) =
            _prepareForLiquidation(fromToken, vaultsToLiquidate);
        _performLiquidation(
            gasBefore, fromToken, asyncSwapper, vaultsToLiquidate, params, totalBalanceToLiquidate, vaultsBalances
        );
    }

    /**
     * @notice Calculates the total balance to liquidate, adjusts the contract state accordingly and calculates fees
     * @dev This function is part of a workaround for the "stack too deep" error and is meant to be used with
     * _performLiquidation. It is not designed to be used standalone, but as part of the liquidateVaultsForToken
     * function
     * @param fromToken The token that needs to be liquidated
     * @param vaultsToLiquidate The list of vaults that need to be liquidated
     * @return totalBalanceToLiquidate The total balance that needs to be liquidated
     * @return vaultsBalances The balances of the vaults
     */
    function _prepareForLiquidation(
        address fromToken,
        IDestinationVault[] memory vaultsToLiquidate
    ) private returns (uint256, uint256[] memory) {
        uint256 length = vaultsToLiquidate.length;

        uint256 totalBalanceToLiquidate = 0;
        uint256[] memory vaultsBalances = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            address vaultAddress = address(vaultsToLiquidate[i]);
            uint256 vaultBalance = balances[fromToken][vaultAddress];
            totalBalanceToLiquidate += vaultBalance;
            vaultsBalances[i] = vaultBalance;
            // Update the total balance for the token
            totalTokenBalances[fromToken] -= vaultBalance;
            // Update the balance for the vault and token
            balances[fromToken][vaultAddress] = 0;
            // Remove the vault from the token vaults list
            if (!tokenVaults[fromToken].remove(vaultAddress)) revert Errors.ItemNotFound();
        }

        if (totalBalanceToLiquidate == 0) {
            revert NothingToLiquidate();
        }

        // Check if the token still has any other vaults
        if (tokenVaults[fromToken].length() == 0) {
            if (!rewardTokens.remove(fromToken)) revert Errors.ItemNotFound();
        }

        return (totalBalanceToLiquidate, vaultsBalances);
    }

    /**
     * @notice Performs the actual liquidation process, handles the async swap, use the price oracle for a fair swap
     * validation, calculates and transfers the fees, and queues the remaining swapped tokens in the MainRewarder
     * associated with each vault.
     * @dev This function is part of a workaround for the "stack too deep" error and is meant to be used with
     * _prepareForLiquidation. It's not designed to be used standalone, but as part of the liquidateVaultsForToken
     * function
     * @param gasBefore Amount of gas when the liquidateVaultsForToken function was called
     * @param fromToken The token that needs to be liquidated
     * @param asyncSwapper The address of the async swapper contract
     * @param vaultsToLiquidate The list of vaults that need to be liquidated
     * @param params Parameters for the async swap
     * @param totalBalanceToLiquidate The total balance that needs to be liquidated
     * @param vaultsBalances The balances of the vaults
     */
    function _performLiquidation(
        uint256 gasBefore,
        address fromToken,
        address asyncSwapper,
        IDestinationVault[] memory vaultsToLiquidate,
        SwapParams memory params,
        uint256 totalBalanceToLiquidate,
        uint256[] memory vaultsBalances
    ) private {
        // Ensure the amount to liquidate matches the vault balance.
        // If not, either the vault balance changed or swapper parameters are incorrect.
        if (params.sellAmount != totalBalanceToLiquidate) {
            revert SellAmountMismatch(totalBalanceToLiquidate, params.sellAmount);
        }
        // Ensure deadline is not exceeded
        // slither-disable-next-line timestamp
        if (block.timestamp > params.deadline) {
            revert DeadlineExceeded(params.deadline, block.timestamp);
        }

        uint256 amountReceived = params.buyAmount;
        uint256 length = vaultsToLiquidate.length;

        // Swap only if the sellToken is different than the vault rewardToken
        if (fromToken != params.buyTokenAddress) {
            // Use the price oracle to ensure we swapped at a fair price
            // Retrieve prices before the swap to ensure accuracy unaffected by market changes.
            IRootPriceOracle oracle = systemRegistry.rootPriceOracle();
            uint256 sellTokenPrice = oracle.getPriceInEth(fromToken);
            uint256 buyTokenPrice = oracle.getPriceInEth(params.buyTokenAddress);

            // the swapper checks that the amount received is greater or equal than the params.buyAmount
            bytes memory data =
                asyncSwapper.functionDelegateCall(abi.encodeCall(IAsyncSwapper.swap, (params)), "SwapFailed");

            amountReceived = abi.decode(data, (uint256));

            // Expected buy amount from Price Oracle
            uint256 expectedBuyAmount = (params.sellAmount * sellTokenPrice) / buyTokenPrice;

            // Allow a margin of error for the swap
            // slither-disable-next-line divide-before-multiply
            uint256 minBuyAmount = (expectedBuyAmount * (MAX_PCT - priceMarginBps)) / MAX_PCT;

            if (amountReceived < minBuyAmount) {
                revert InsufficientAmountReceived(minBuyAmount, amountReceived);
            }
        } else {
            // Ensure that if no swap is needed, the sell and buy amounts are the same.
            if (params.sellAmount != params.buyAmount) revert AmountsMismatch(params.sellAmount, params.buyAmount);
        }

        // if the fee feature is turned on, send the fee to the fee receiver
        if (feeReceiver != address(0) && feeBps > 0) {
            uint256 fee = calculateFee(amountReceived);
            emit FeesTransferred(feeReceiver, amountReceived, fee);

            // adjust the amount received after deducting the fee
            amountReceived -= fee;
            // transfer fee to the fee receiver
            IERC20(params.buyTokenAddress).safeTransfer(feeReceiver, fee);
        }

        uint256 gasUsedPerVault = (gasBefore - gasleft()) / vaultsToLiquidate.length;
        uint256 totalAmounts = 0;
        for (uint256 i = 0; i < length;) {
            IDestinationVault vaultAddress = vaultsToLiquidate[i];
            IMainRewarder mainRewarder = IMainRewarder(vaultAddress.rewarder());

            if (mainRewarder.rewardToken() != params.buyTokenAddress) {
                revert InvalidRewardToken();
            }

            // last vault clears all the dust
            uint256 amount;
            if (i == length - 1) {
                amount = amountReceived - totalAmounts;
            } else {
                amount = amountReceived * vaultsBalances[i] / totalBalanceToLiquidate;
                totalAmounts += amount;
            }

            // approve main rewarder to pull the tokens
            LibAdapter._approve(IERC20(params.buyTokenAddress), address(mainRewarder), amount);
            mainRewarder.queueNewRewards(amount);

            emit VaultLiquidated(address(vaultAddress), fromToken, params.buyTokenAddress, amount);
            emit GasUsedForVault(address(vaultAddress), gasUsedPerVault, bytes32("liquidation"));

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Update the balance of a specific token and vault
     * @param tokenAddress The address of the token
     * @param vaultAddress The address of the vault
     * @param balance The amount of the token to be updated
     */
    function _increaseBalance(address tokenAddress, address vaultAddress, uint256 balance) internal {
        Errors.verifyNotZero(balance, "balance");

        uint256 currentBalance = balances[tokenAddress][vaultAddress];
        uint256 totalBalance = totalTokenBalances[tokenAddress];
        uint256 newTotalBalance = totalBalance + balance;

        // ensure that this contract has enough balance to cover the new total balance
        uint256 balanceOfToken = IERC20(tokenAddress).balanceOf(address(this));
        if (newTotalBalance > balanceOfToken) {
            /**
             * @dev This should never happen, but just in case. The error is raised if the updated total balance of a
             * specific token in the contract is greater than the actual balance of that token held by the
             * contract.
             * The calling contract should transfer the funds first before updating the balance.
             */
            revert Errors.InsufficientBalance(tokenAddress);
        }

        // if currentBalance is 0, then the vault is not yet added to the token vaults list
        if (currentBalance == 0) {
            if (!tokenVaults[tokenAddress].add(vaultAddress)) revert Errors.ItemExists();

            if (totalBalance == 0) {
                if (!rewardTokens.add(tokenAddress)) revert Errors.ItemExists();
            }
        }

        // Update the total balance for the token
        totalTokenBalances[tokenAddress] = newTotalBalance;
        // Update the balance for the vault and token
        balances[tokenAddress][vaultAddress] = currentBalance + balance;

        emit BalanceUpdated(tokenAddress, vaultAddress, currentBalance + balance);
    }

    function _setPriceMarginBps(
        uint256 _priceMarginBps
    ) private {
        // Want to limit the price margin to 10%.
        if (_priceMarginBps > MAX_PCT / 10) revert Errors.InvalidParam("priceMarginBps");
        priceMarginBps = _priceMarginBps;

        emit PriceMarginSet(_priceMarginBps);
    }
}
