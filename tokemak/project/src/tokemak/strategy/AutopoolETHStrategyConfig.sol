// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { NavTracking } from "src/tokemak/strategy/NavTracking.sol";

library AutopoolETHStrategyConfig {
    uint256 private constant WEIGHT_MAX = 1e6;
    int256 private constant WEIGHT_MAX_I = 1e6;

    error InvalidConfig(string paramName);

    // TODO: switch swapCostOffset from days to seconds; possibly pauseRebalance too
    struct StrategyConfig {
        SwapCostOffsetConfig swapCostOffset;
        NavLookbackConfig navLookback;
        SlippageConfig slippage;
        ModelWeights modelWeights;
        // number of days to pause rebalancing if a long-term nav decay is detected
        uint16 pauseRebalancePeriodInDays;
        // number of seconds before next rebalance can occur
        uint256 rebalanceTimeGapInSeconds;
        // destinations trading a premium above maxPremium will be blocked from new capital deployments
        int256 maxPremium; // 100% = 1e18
        // destinations trading a discount above maxDiscount will be blocked from new capital deployments
        int256 maxDiscount; // 100% = 1e18
        // if any stats data is older than this, rebalancing will revert
        uint40 staleDataToleranceInSeconds;
        // the maximum discount incorporated in price return
        int256 maxAllowedDiscount;
        // the maximum deviation between spot & safe price for individual LSTs
        uint256 lstPriceGapTolerance;
        // Array of hooks.  Up to five hooks on AutopoolEth strategy, can be address(0)
        address[5] hooks;
    }

    struct SwapCostOffsetConfig {
        // the swap cost offset period to initialize the strategy with
        uint16 initInDays;
        // the number of violations required to trigger a tightening of the swap cost offset period (1 to 10)
        uint16 tightenThresholdInViolations;
        // the number of days to decrease the swap offset period for each tightening step
        uint16 tightenStepInDays;
        // the number of days since a rebalance required to trigger a relaxing of the swap cost offset period
        uint16 relaxThresholdInDays;
        // the number of days to increase the swap offset period for each relaxing step
        uint16 relaxStepInDays;
        // the maximum the swap cost offset period can reach. This is the loosest the strategy will be
        uint16 maxInDays;
        // the minimum the swap cost offset period can reach. This is the most conservative the strategy will be
        uint16 minInDays;
    }

    struct NavLookbackConfig {
        // the number of days for the first NAV decay comparison (e.g., 30 days)
        uint8 lookback1InDays;
        // the number of days for the second NAV decay comparison (e.g., 60 days)
        uint8 lookback2InDays;
        // the number of days for the third NAV decay comparison (e.g., 90 days)
        uint8 lookback3InDays;
    }

    struct SlippageConfig {
        // the maximum slippage that is allowed for a normal rebalance
        // under normal circumstances this will not be triggered because the swap offset logic is the primary gate
        // but this ensures a sensible slippage level will never be exceeded
        uint256 maxNormalOperationSlippage; // 100% = 1e18
        // the maximum amount of slippage to allow when a destination is trimmed due to constraint violations
        // recommend setting this higher than maxNormalOperationSlippage
        uint256 maxTrimOperationSlippage; // 100% = 1e18
        // the maximum amount of slippage to allow when a destinationVault has been shutdown
        // shutdown for a vault is abnormal and means there is an issue at that destination
        // recommend setting this higher than maxNormalOperationSlippage
        uint256 maxEmergencyOperationSlippage; // 100% = 1e18
        // the maximum amount of slippage to allow when the Autopool has been shutdown
        uint256 maxShutdownOperationSlippage; // 100% = 1e18
    }

    struct ModelWeights {
        uint256 baseYield;
        uint256 feeYield;
        uint256 incentiveYield;
        int256 priceDiscountExit;
        int256 priceDiscountEnter;
        int256 pricePremium;
    }

    // slither-disable-start cyclomatic-complexity

    function validate(
        StrategyConfig memory config
    ) internal pure {
        // Swap Cost Offset Config

        if (
            config.swapCostOffset.initInDays < config.swapCostOffset.minInDays
                || config.swapCostOffset.initInDays > config.swapCostOffset.maxInDays
                || config.swapCostOffset.initInDays < 7 || config.swapCostOffset.initInDays > 90
        ) {
            revert InvalidConfig("swapCostOffset_initInDays");
        }

        if (
            config.swapCostOffset.tightenThresholdInViolations < 1
                || config.swapCostOffset.tightenThresholdInViolations > 10
        ) {
            revert InvalidConfig("swapCostOffset_tightenThresholdInViolations");
        }

        if (config.swapCostOffset.tightenStepInDays < 1 || config.swapCostOffset.tightenStepInDays > 7) {
            revert InvalidConfig("swapCostOffset_tightenStepInDays");
        }

        if (config.swapCostOffset.relaxThresholdInDays < 14 || config.swapCostOffset.relaxThresholdInDays > 90) {
            revert InvalidConfig("swapCostOffset_relaxThresholdInDays");
        }

        if (config.swapCostOffset.relaxStepInDays < 1 || config.swapCostOffset.relaxStepInDays > 7) {
            revert InvalidConfig("swapCostOffset_relaxStepInDays");
        }

        if (
            config.swapCostOffset.maxInDays <= config.swapCostOffset.minInDays || config.swapCostOffset.maxInDays < 8
                || config.swapCostOffset.maxInDays > 90
        ) {
            revert InvalidConfig("swapCostOffset_maxInDays");
        }

        if (config.swapCostOffset.minInDays < 7 || config.swapCostOffset.minInDays > 90) {
            revert InvalidConfig("swapCostOffset_minInDays");
        }

        // NavLookback

        _validateNotZero(config.navLookback.lookback1InDays, "navLookback_lookback1InDays");

        // the 91st spot holds current (0 days ago), so the farthest back that can be retrieved is 90 days ago
        if (
            config.navLookback.lookback1InDays >= NavTracking.MAX_NAV_TRACKING
                || config.navLookback.lookback2InDays >= NavTracking.MAX_NAV_TRACKING
                || config.navLookback.lookback3InDays > NavTracking.MAX_NAV_TRACKING
        ) {
            revert InvalidConfig("navLookback_max");
        }

        // lookback should be configured smallest to largest and should not be equal
        if (
            config.navLookback.lookback1InDays >= config.navLookback.lookback2InDays
                || config.navLookback.lookback2InDays >= config.navLookback.lookback3InDays
        ) {
            revert InvalidConfig("navLookback_steps");
        }

        // Slippage

        _ensureNotGt25PctE18(config.slippage.maxShutdownOperationSlippage, "slippage_maxShutdownOperationSlippage");
        _ensureNotGt25PctE18(config.slippage.maxEmergencyOperationSlippage, "slippage_maxEmergencyOperationSlippage");
        _ensureNotGt25PctE18(config.slippage.maxTrimOperationSlippage, "slippage_maxTrimOperationSlippage");
        _ensureNotGt25PctE18(config.slippage.maxNormalOperationSlippage, "slippage_maxNormalOperationSlippage");

        // Model Weights

        if (config.modelWeights.baseYield > WEIGHT_MAX) {
            revert InvalidConfig("modelWeights_baseYield");
        }

        if (config.modelWeights.feeYield > WEIGHT_MAX) {
            revert InvalidConfig("modelWeights_feeYield");
        }

        if (config.modelWeights.incentiveYield > WEIGHT_MAX) {
            revert InvalidConfig("modelWeights_incentiveYield");
        }

        if (config.modelWeights.priceDiscountExit > WEIGHT_MAX_I) {
            revert InvalidConfig("modelWeights_priceDiscountExit");
        }

        if (config.modelWeights.priceDiscountEnter > WEIGHT_MAX_I) {
            revert InvalidConfig("modelWeights_priceDiscountEnter");
        }

        if (config.modelWeights.pricePremium > WEIGHT_MAX_I) {
            revert InvalidConfig("modelWeights_pricePremium");
        }

        // Top Level Config

        if (config.pauseRebalancePeriodInDays < 7 || config.pauseRebalancePeriodInDays > 90) {
            revert InvalidConfig("pauseRebalancePeriodInDays");
        }

        if (config.rebalanceTimeGapInSeconds < 1 hours || config.rebalanceTimeGapInSeconds > 30 days) {
            revert InvalidConfig("rebalanceTimeGapInSeconds");
        }

        _ensureNotGt25PctE18OrLtZero(config.maxPremium, "maxPremium");
        _ensureNotGt25PctE18OrLtZero(config.maxDiscount, "maxPremium");

        if (config.staleDataToleranceInSeconds < 1 hours || config.staleDataToleranceInSeconds > 7 days) {
            revert InvalidConfig("staleDataToleranceInSeconds");
        }

        if (config.maxAllowedDiscount < 0 || config.maxAllowedDiscount > 0.5e18) {
            revert InvalidConfig("maxAllowedDiscount");
        }

        if (config.lstPriceGapTolerance > 500) {
            revert InvalidConfig("lstPriceGapTolerance");
        }

        _validateHooks(config.hooks);
    }

    // slither-disable-end cyclomatic-complexity

    function _validateNotZero(uint256 val, string memory err) private pure {
        if (val == 0) {
            revert InvalidConfig(err);
        }
    }

    function _ensureNotGt25PctE18(uint256 value, string memory err) private pure {
        if (value > 0.25e18) {
            revert InvalidConfig(err);
        }
    }

    function _ensureNotGt25PctE18OrLtZero(int256 value, string memory err) private pure {
        if (value > 0.25e18 || value < 0) {
            revert InvalidConfig(err);
        }
    }

    // Checks to make sure that there are no zero address gaps in hooks array
    function _validateHooks(
        address[5] memory hooks
    ) private pure {
        // slither-disable-next-line uninitialized-local
        bool zeroAddressReached;
        for (uint256 i = 0; i < 5; ++i) {
            address currentHook = hooks[i];

            // If we reach a zero address for the first time, flip flag to true
            if (currentHook == address(0) && !zeroAddressReached) {
                zeroAddressReached = true;
            }

            // If this gets triggered there is a set hook after a zero address hook.  Revert as this
            // is not an expected state
            if (zeroAddressReached && currentHook != address(0)) {
                revert InvalidConfig("hooks");
            }
        }
    }
}
