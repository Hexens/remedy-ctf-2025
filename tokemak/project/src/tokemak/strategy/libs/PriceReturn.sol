// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { StrategyUtils } from "src/tokemak/strategy/libs/StrategyUtils.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";

library PriceReturn {
    function calculateWeightedPriceReturn(
        int256 priceReturn,
        uint256 reserveValue,
        IAutopoolStrategy.RebalanceDirection direction
    ) external view returns (int256) {
        IAutopoolStrategy strategy = IAutopoolStrategy(address(this));

        // slither-disable-next-line timestamp
        if (priceReturn > 0) {
            // LST trading at a discount
            if (direction == IAutopoolStrategy.RebalanceDirection.Out) {
                return priceReturn * StrategyUtils.convertUintToInt(reserveValue) * strategy.weightPriceDiscountExit()
                    / 1e6;
            } else {
                return priceReturn * StrategyUtils.convertUintToInt(reserveValue) * strategy.weightPriceDiscountEnter()
                    / 1e6;
            }
        } else {
            // LST trading at 0 or a premium
            return priceReturn * StrategyUtils.convertUintToInt(reserveValue) * strategy.weightPricePremium() / 1e6;
        }
    }

    function calculatePriceReturns(
        IDexLSTStats.DexLSTStatsData memory stats
    ) external view returns (int256[] memory) {
        IAutopoolStrategy strategy = IAutopoolStrategy(address(this));

        ILSTStats.LSTStatsData[] memory lstStatsData = stats.lstStatsData;

        uint256 numLsts = lstStatsData.length;
        int256[] memory priceReturns = new int256[](numLsts);
        int256 maxDiscount = strategy.maxAllowedDiscount();

        for (uint256 i = 0; i < numLsts; ++i) {
            ILSTStats.LSTStatsData memory data = lstStatsData[i];

            uint256 scalingFactor = 1e18; // default scalingFactor is 1

            int256 discount = data.discount;
            if (discount > maxDiscount) {
                discount = maxDiscount;
            }

            // discount value that is negative indicates LST price premium
            // scalingFactor = 1e18 for premiums and discounts that are small
            // discountTimestampByPercent holds the timestamp for 1% discount
            uint40 discountTimestampByPercent = data.discountTimestampByPercent;

            // 1e16 means a 1% LST discount where full scale is 1e18.
            if ((discount > 1e16) && (discountTimestampByPercent > 0)) {
                // linear approximation for exponential function with approx. half life of 30 days
                uint256 halfLifeSec = 30 * 24 * 60 * 60;
                // current timestamp should be strictly >= timestamp in discountTimestampByPercent
                uint256 timeSinceDiscountSec = uint256(uint40(block.timestamp) - discountTimestampByPercent);
                scalingFactor >>= (timeSinceDiscountSec / halfLifeSec);
                // slither-disable-next-line weak-prng
                timeSinceDiscountSec %= halfLifeSec;
                scalingFactor -= scalingFactor * timeSinceDiscountSec / halfLifeSec / 2;
            }
            priceReturns[i] = discount * StrategyUtils.convertUintToInt(scalingFactor) / 1e18;
        }

        return priceReturns;
    }
}
