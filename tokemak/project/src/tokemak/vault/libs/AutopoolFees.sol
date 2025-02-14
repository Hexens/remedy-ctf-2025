// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { AutopoolToken } from "src/tokemak/vault/libs/AutopoolToken.sol";

library AutopoolFees {
    using Math for uint256;
    using AutopoolToken for AutopoolToken.TokenData;

    /// @notice Profit denomination
    uint256 public constant MAX_BPS_PROFIT = 1_000_000_000;

    /// @notice 100% == 10000
    uint256 public constant FEE_DIVISOR = 10_000;

    /// @notice Max periodic fee, 10%.  100% = 10_000.
    uint256 public constant MAX_PERIODIC_FEE_BPS = 1000;

    uint256 public constant SECONDS_IN_YEAR = 365 * 1 days;

    event FeeCollected(uint256 fees, address feeSink, uint256 mintedShares, uint256 profit, uint256 totalAssets);
    event PeriodicFeeCollected(uint256 fees, address feeSink, uint256 mintedShares);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event PeriodicFeeSet(uint256 newFee);
    event PeriodicFeeSinkSet(address newPeriodicFeeSink);
    event LastPeriodicFeeTakeSet(uint256 lastPeriodicFeeTake);
    event RebalanceFeeHighWaterMarkEnabledSet(bool enabled);
    event NewNavShareFeeMark(uint256 navPerShare, uint256 timestamp);
    event NewTotalAssetsHighWatermark(uint256 assets, uint256 timestamp);
    event StreamingFeeSet(uint256 newFee);
    event FeeSinkSet(address newFeeSink);
    event NewProfitUnlockTime(uint48 timeSeconds);

    error InvalidFee(uint256 newFee);
    error AlreadySet();
    error DebtReportingStale();

    /// @notice Returns the amount of unlocked profit shares that will be burned
    function unlockedShares(
        IAutopool.ProfitUnlockSettings storage profitUnlockSettings,
        AutopoolToken.TokenData storage tokenData
    ) public view returns (uint256 shares) {
        uint256 fullTime = profitUnlockSettings.fullProfitUnlockTime;
        if (fullTime > block.timestamp) {
            shares = profitUnlockSettings.profitUnlockRate
                * (block.timestamp - profitUnlockSettings.lastProfitUnlockTime) / MAX_BPS_PROFIT;
        } else if (fullTime != 0) {
            shares = tokenData.balances[address(this)];
        }
    }

    function initializeFeeSettings(
        IAutopool.AutopoolFeeSettings storage settings
    ) external {
        uint256 timestamp = block.timestamp;
        settings.lastPeriodicFeeTake = timestamp; // Stops fees from being able to be claimed before init timestamp.
        settings.navPerShareLastFeeMark = FEE_DIVISOR;
        settings.navPerShareLastFeeMarkTimestamp = timestamp;
        emit LastPeriodicFeeTakeSet(timestamp);
    }

    function burnUnlockedShares(
        IAutopool.ProfitUnlockSettings storage profitUnlockSettings,
        AutopoolToken.TokenData storage tokenData
    ) external {
        uint256 shares = unlockedShares(profitUnlockSettings, tokenData);
        if (shares == 0) {
            return;
        }
        if (profitUnlockSettings.fullProfitUnlockTime > block.timestamp) {
            profitUnlockSettings.lastProfitUnlockTime = uint48(block.timestamp);
        }
        tokenData.burn(address(this), shares);
    }

    function _calculateEffectiveNavPerShareLastFeeMark(
        IAutopool.AutopoolFeeSettings storage settings,
        uint256 currentBlock,
        uint256 currentNavPerShare,
        uint256 aumCurrent
    ) private view returns (uint256) {
        uint256 workingHigh = settings.navPerShareLastFeeMark;

        if (workingHigh == 0) {
            // If we got 0, we shouldn't increase it
            return 0;
        }

        if (!settings.rebalanceFeeHighWaterMarkEnabled) {
            // No calculations or checks to do in this case
            return workingHigh;
        }

        uint256 daysSinceLastFeeEarned = (currentBlock - settings.navPerShareLastFeeMarkTimestamp) / 60 / 60 / 24;

        if (daysSinceLastFeeEarned > 600) {
            return currentNavPerShare;
        }
        if (daysSinceLastFeeEarned > 60 && daysSinceLastFeeEarned <= 600) {
            uint8 decimals = IAutopool(address(this)).decimals();

            uint256 one = 10 ** decimals;
            uint256 aumHighMark = settings.totalAssetsHighMark;

            // AUM_min = min(AUM_high, AUM_current)
            uint256 minAssets = aumCurrent < aumHighMark ? aumCurrent : aumHighMark;

            // AUM_max = max(AUM_high, AUM_current);
            uint256 maxAssets = aumCurrent > aumHighMark ? aumCurrent : aumHighMark;

            /// 0.999 * (AUM_min / AUM_max)
            // dividing by `one` because we need end up with a number in the 100's wei range
            uint256 g1 = ((999 * minAssets * one) / (maxAssets * one));

            /// 0.99 * (1 - AUM_min / AUM_max)
            // dividing by `10 ** (decimals() - 1)` because we need to divide 100 out for our % and then
            // we want to end up with a number in the 10's wei range
            uint256 g2 = (99 * (one - (minAssets * one / maxAssets))) / 10 ** (decimals - 1);

            uint256 gamma = g1 + g2;

            uint256 daysDiff = daysSinceLastFeeEarned - 60;
            for (uint256 i = 0; i < daysDiff / 25; ++i) {
                // slither-disable-next-line divide-before-multiply
                workingHigh = workingHigh * (gamma ** 25 / 1e72) / 1000;
            }
            // slither-disable-next-line weak-prng
            for (uint256 i = 0; i < daysDiff % 25; ++i) {
                // slither-disable-next-line divide-before-multiply
                workingHigh = workingHigh * gamma / 1000;
            }
        }
        return workingHigh;
    }

    function collectFees(
        uint256 totalAssets,
        uint256 currentTotalSupply,
        IAutopool.AutopoolFeeSettings storage settings,
        AutopoolToken.TokenData storage tokenData,
        bool collectPeriodicFees
    ) external returns (uint256) {
        // If there's no supply then there should be no assets and so nothing
        // to actually take fees on
        // slither-disable-next-line incorrect-equality
        if (currentTotalSupply == 0) {
            return 0;
        }

        // slither-disable-start timestamp
        if (collectPeriodicFees) {
            address periodicFeeSink = settings.periodicFeeSink;
            uint256 periodicFeeBps = settings.periodicFeeBps;
            // If there is a periodic fee and fee sink set, take the fee.
            if (periodicFeeBps > 0 && periodicFeeSink != address(0)) {
                uint256 durationSinceLastPeriodicFeeTake = block.timestamp - settings.lastPeriodicFeeTake;
                uint256 timeAdjustedBps = durationSinceLastPeriodicFeeTake.mulDiv(
                    periodicFeeBps * FEE_DIVISOR, SECONDS_IN_YEAR, Math.Rounding.Up
                );

                uint256 periodicShares =
                    _collectPeriodicFees(periodicFeeSink, timeAdjustedBps, currentTotalSupply, totalAssets);

                currentTotalSupply += periodicShares;
                tokenData.mint(periodicFeeSink, periodicShares);
            }

            // Needs to be kept up to date so if a fee is suddenly turned on a large part of assets do not get
            // claimed as fees.
            settings.lastPeriodicFeeTake = block.timestamp;
            emit LastPeriodicFeeTakeSet(block.timestamp);
        }

        // slither-disable-end timestamp
        uint256 currentNavPerShare = (totalAssets * FEE_DIVISOR) / currentTotalSupply;

        // If the high mark is disabled then this just returns the `navPerShareLastFeeMark`
        // Otherwise, it'll check if it needs to decay
        uint256 effectiveNavPerShareLastFeeMark =
            _calculateEffectiveNavPerShareLastFeeMark(settings, block.timestamp, currentNavPerShare, totalAssets);

        if (currentNavPerShare > effectiveNavPerShareLastFeeMark) {
            // Even if we aren't going to take the fee (haven't set a sink)
            // We still want to calculate so we can emit for off-chain analysis
            uint256 profit = (currentNavPerShare - effectiveNavPerShareLastFeeMark) * currentTotalSupply;
            uint256 fees = profit.mulDiv(settings.streamingFeeBps, (FEE_DIVISOR ** 2), Math.Rounding.Up);

            if (fees > 0) {
                currentTotalSupply = _mintStreamingFee(
                    tokenData, fees, settings.streamingFeeBps, profit, currentTotalSupply, totalAssets, settings.feeSink
                );
                currentNavPerShare = (totalAssets * FEE_DIVISOR) / currentTotalSupply;
            }
        }

        // Two situations we're covering here
        //   1. If the high mark is disabled then we just always need to know the last
        //      time we evaluated fees so we can catch any run up. i.e. the `navPerShareLastFeeMark`
        //      can go down
        //   2. When the high mark is enabled, then we only want to set `navPerShareLastFeeMark`
        //      when it is greater than the last time we captured fees (or would have)
        if (currentNavPerShare >= effectiveNavPerShareLastFeeMark || !settings.rebalanceFeeHighWaterMarkEnabled) {
            settings.navPerShareLastFeeMark = currentNavPerShare;
            settings.navPerShareLastFeeMarkTimestamp = block.timestamp;
            emit NewNavShareFeeMark(currentNavPerShare, block.timestamp);
        }

        // Set our new high water mark for totalAssets, regardless if we took fees
        if (settings.totalAssetsHighMark < totalAssets) {
            settings.totalAssetsHighMark = totalAssets;
            settings.totalAssetsHighMarkTimestamp = block.timestamp;
            emit NewTotalAssetsHighWatermark(settings.totalAssetsHighMark, settings.totalAssetsHighMarkTimestamp);
        }

        return currentTotalSupply;
    }

    function _mintStreamingFee(
        AutopoolToken.TokenData storage tokenData,
        uint256 fees,
        uint256 streamingFeeBps,
        uint256 profit,
        uint256 currentTotalSupply,
        uint256 totalAssets,
        address sink
    ) private returns (uint256) {
        if (sink == address(0)) {
            return currentTotalSupply;
        }

        uint256 streamingFeeShares =
            _calculateSharesToMintFeeCollection(streamingFeeBps, profit, totalAssets, currentTotalSupply);
        tokenData.mint(sink, streamingFeeShares);
        currentTotalSupply += streamingFeeShares;

        emit Deposit(address(this), sink, 0, streamingFeeShares);
        emit FeeCollected(fees, sink, streamingFeeShares, profit, totalAssets);

        return currentTotalSupply;
    }

    /// @dev Collects periodic fees.
    function _collectPeriodicFees(
        address periodicSink,
        uint256 timeAdjustedFeeBps,
        uint256 currentTotalSupply,
        uint256 totalAssets
    ) private returns (uint256 newShares) {
        newShares =
            _calculateSharesToMintFeeCollection(timeAdjustedFeeBps, totalAssets, totalAssets, currentTotalSupply);

        // Fee in assets that we are taking.
        uint256 fees = (timeAdjustedFeeBps * totalAssets / FEE_DIVISOR).ceilDiv(FEE_DIVISOR);
        emit Deposit(address(this), periodicSink, 0, newShares);
        emit PeriodicFeeCollected(fees, periodicSink, newShares);

        return newShares;
    }

    function _calculateSharesToMintFeeCollection(
        uint256 feeBps,
        uint256 amountForFee,
        uint256 totalAssets,
        uint256 totalSupply
    ) private pure returns (uint256 toMint) {
        // Gas savings, this is used twice.
        uint256 feeTotalAssets = feeBps * amountForFee / FEE_DIVISOR;

        // Separate from other mints as normal share mint is round down
        // Mints shares taking into account the dilution so we end up with the expected amount
        // `feeBps` is padded by FEE_DIVISOR when taking periodic fee
        // `amountForFee` is padded by FEE_DIVISOR when taking streaming fee
        toMint =
            Math.mulDiv(feeTotalAssets, totalSupply, (totalAssets * FEE_DIVISOR) - (feeTotalAssets), Math.Rounding.Up);
    }

    /// @dev If set to 0, existing shares will unlock immediately and increase nav/share. This is intentional
    function setProfitUnlockPeriod(
        IAutopool.ProfitUnlockSettings storage settings,
        AutopoolToken.TokenData storage tokenData,
        uint48 newUnlockPeriodInSeconds
    ) external {
        settings.unlockPeriodInSeconds = newUnlockPeriodInSeconds;

        // If we are turning off the unlock, setting it to 0, then
        // unlock all existing shares
        if (newUnlockPeriodInSeconds == 0) {
            uint256 currentShares = tokenData.balances[address(this)];
            if (currentShares > 0) {
                settings.lastProfitUnlockTime = uint48(block.timestamp);
                tokenData.burn(address(this), currentShares);
            }

            // Reset vars so old values aren't used during a subsequent lockup
            settings.fullProfitUnlockTime = 0;
            settings.profitUnlockRate = 0;
        }

        emit NewProfitUnlockTime(newUnlockPeriodInSeconds);
    }

    function calculateProfitLocking(
        IAutopool.ProfitUnlockSettings storage settings,
        AutopoolToken.TokenData storage tokenData,
        uint256 feeShares,
        uint256 newTotalAssets,
        uint256 startTotalAssets,
        uint256 startTotalSupply,
        uint256 previousLockShares
    ) external returns (uint256) {
        uint256 unlockPeriod = settings.unlockPeriodInSeconds;

        // If there were existing shares and we set the unlock period to 0 they are immediately unlocked
        // so we don't have to worry about existing shares here. And if the period is 0 then we
        // won't be locking any new shares
        if (unlockPeriod == 0 || startTotalAssets == 0) {
            return startTotalSupply;
        }

        uint256 newLockShares = 0;
        uint256 previousLockToBurn = 0;
        uint256 effectiveTs = startTotalSupply;

        // The total supply we would need to not see a change in nav/share
        uint256 targetTotalSupply = newTotalAssets * (effectiveTs - feeShares) / startTotalAssets;

        if (effectiveTs > targetTotalSupply) {
            // Our actual total supply is greater than our target.
            // This means we would see a decrease in nav/share
            // See if we can burn any profit shares to offset that
            if (previousLockShares > 0) {
                uint256 diff = effectiveTs - targetTotalSupply;
                if (previousLockShares >= diff) {
                    previousLockToBurn = diff;
                    effectiveTs -= diff;
                } else {
                    previousLockToBurn = previousLockShares;
                    effectiveTs -= previousLockShares;
                }
            }
        }

        if (targetTotalSupply > effectiveTs) {
            // Our actual total supply is less than our target.
            // This means we would see an increase in nav/share (due to gains) which we can't allow
            // We need to mint shares to the vault to offset
            newLockShares = targetTotalSupply - effectiveTs;
            effectiveTs += newLockShares;
        }

        // We know how many shares should be locked at this point
        // Mint or burn what we need to match if necessary
        uint256 totalLockShares = previousLockShares - previousLockToBurn + newLockShares;
        if (totalLockShares > previousLockShares) {
            uint256 mintAmount = totalLockShares - previousLockShares;
            tokenData.mint(address(this), mintAmount);
            startTotalSupply += mintAmount;
        } else if (totalLockShares < previousLockShares) {
            uint256 burnAmount = previousLockShares - totalLockShares;
            tokenData.burn(address(this), burnAmount);
            startTotalSupply -= burnAmount;
        }

        // If we're going to end up with no profit shares, zero the rate
        // We don't need to 0 the other timing vars if we just zero the rate
        if (totalLockShares == 0) {
            settings.profitUnlockRate = 0;
        }

        // We have shares and they are going to unlocked later
        if (totalLockShares > 0 && unlockPeriod > 0) {
            _updateProfitUnlockTimings(
                settings, unlockPeriod, previousLockToBurn, previousLockShares, newLockShares, totalLockShares
            );
        }

        return startTotalSupply;
    }

    function _updateProfitUnlockTimings(
        IAutopool.ProfitUnlockSettings storage settings,
        uint256 unlockPeriod,
        uint256 previousLockToBurn,
        uint256 previousLockShares,
        uint256 newLockShares,
        uint256 totalLockShares
    ) private {
        uint256 previousLockTime;
        uint256 fullUnlockTime = settings.fullProfitUnlockTime;

        // Determine how much time is left for the remaining previous profit shares
        if (fullUnlockTime > block.timestamp) {
            previousLockTime = (previousLockShares - previousLockToBurn) * (fullUnlockTime - block.timestamp);
        }

        // Amount of time it will take to unlock all shares, weighted avg over current and new shares
        uint256 newUnlockPeriod = (previousLockTime + newLockShares * unlockPeriod) / totalLockShares;

        if (newUnlockPeriod == 0) {
            settings.profitUnlockRate = 0;
        } else {
            // Rate at which totalLockShares will unlock
            settings.profitUnlockRate = totalLockShares * MAX_BPS_PROFIT / newUnlockPeriod;
        }

        // Time the full of amount of totalLockShares will be unlocked
        settings.fullProfitUnlockTime = uint48(block.timestamp + newUnlockPeriod);
        settings.lastProfitUnlockTime = uint48(block.timestamp);
    }

    /// @notice Enable or disable the high water mark on the rebalance fee
    /// @dev Will revert if set to the same value
    function setRebalanceFeeHighWaterMarkEnabled(
        IAutopool.AutopoolFeeSettings storage feeSettings,
        bool enabled
    ) external {
        if (feeSettings.rebalanceFeeHighWaterMarkEnabled == enabled) {
            revert AlreadySet();
        }

        feeSettings.rebalanceFeeHighWaterMarkEnabled = enabled;

        emit RebalanceFeeHighWaterMarkEnabledSet(enabled);
    }

    /// @notice Set the fee that will be taken when profit is realized
    /// @dev Resets the high water to current value
    /// @param fee Percent. 100% == 10000
    /// @param oldestDebtReporting Debt reporting timestamp to be checked
    /// @param debtReportQueueLength Total length of the debt reporting queue
    function setStreamingFeeBps(
        IAutopool.AutopoolFeeSettings storage feeSettings,
        uint256 fee,
        uint256 oldestDebtReporting,
        uint256 debtReportQueueLength
    ) external {
        if (fee >= FEE_DIVISOR) {
            revert InvalidFee(fee);
        }

        _checkLastDebtReportingTime(oldestDebtReporting, debtReportQueueLength);

        IAutopool vault = IAutopool(address(this));

        feeSettings.streamingFeeBps = fee;

        // Set the high mark when we change the fee so we aren't able to go farther back in
        // time than one debt reporting and claim fee's against past profits
        uint256 ts = vault.totalSupply();
        if (ts > 0) {
            uint256 ta = vault.totalAssets();
            if (ta > 0) {
                feeSettings.navPerShareLastFeeMark = (ta * FEE_DIVISOR) / ts;
            } else {
                feeSettings.navPerShareLastFeeMark = FEE_DIVISOR;
            }
        }
        emit StreamingFeeSet(fee);
    }

    /// @notice Set the periodic fee taken.
    /// @dev Zero is allowed, no fee taken.
    /// @param fee Fee to update periodic fee to.
    /// @param oldestDebtReporting Debt reporting timestamp to be checked
    /// @param debtReportQueueLength Total length of the debt reporting queue
    function setPeriodicFeeBps(
        IAutopool.AutopoolFeeSettings storage feeSettings,
        uint256 fee,
        uint256 oldestDebtReporting,
        uint256 debtReportQueueLength
    ) external {
        if (fee > MAX_PERIODIC_FEE_BPS) {
            revert InvalidFee(fee);
        }

        _checkLastDebtReportingTime(oldestDebtReporting, debtReportQueueLength);

        // Fee checked to fit into uint16 above, able to be wrapped without safe cast here.
        emit PeriodicFeeSet(fee);
        feeSettings.periodicFeeBps = uint16(fee);
    }

    /// @notice Set the address that will receive fees
    /// @param newFeeSink Address that will receive fees
    function setFeeSink(IAutopool.AutopoolFeeSettings storage feeSettings, address newFeeSink) external {
        emit FeeSinkSet(newFeeSink);

        // Zero is valid. One way to disable taking fees
        // slither-disable-next-line missing-zero-check
        feeSettings.feeSink = newFeeSink;
    }

    /// @notice Sets the address that will receive periodic fees.
    /// @dev Zero address allowable.  Disables fees.
    /// @param newPeriodicFeeSink New periodic fee address.
    function setPeriodicFeeSink(
        IAutopool.AutopoolFeeSettings storage feeSettings,
        address newPeriodicFeeSink
    ) external {
        emit PeriodicFeeSinkSet(newPeriodicFeeSink);

        // slither-disable-next-line missing-zero-check
        feeSettings.periodicFeeSink = newPeriodicFeeSink;
    }

    function _checkLastDebtReportingTime(uint256 oldestDebtReporting, uint256 debtReportQueueLength) private view {
        if (debtReportQueueLength > 0 && oldestDebtReporting < block.timestamp - 10 minutes) {
            revert DebtReportingStale();
        }
    }
}
