// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { IIncentivesPricingStats } from "src/tokemak/interfaces/stats/IIncentivesPricingStats.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";

library Incentives {
    using Math for uint256;

    // when removing liquidity, rewards can be expired by this amount if the pool as incentive credits
    uint256 public constant EXPIRED_REWARD_TOLERANCE = 7 days;

    function calculateIncentiveApr(
        IIncentivesPricingStats pricing,
        IDexLSTStats.StakingIncentiveStats memory stats,
        IAutopoolStrategy.RebalanceDirection direction,
        address destAddress,
        uint256 lpAmountToAddOrRemove,
        uint256 lpPrice
    ) external view returns (uint256) {
        uint40 staleDataToleranceInSeconds = IAutopoolStrategy(address(this)).staleDataToleranceInSeconds();

        bool hasCredits = stats.incentiveCredits > 0;
        uint256 totalRewards = 0;

        uint256 numRewards = stats.annualizedRewardAmounts.length;
        for (uint256 i = 0; i < numRewards; ++i) {
            address rewardToken = stats.rewardTokens[i];
            // Move ahead only if the rewardToken is not 0
            if (rewardToken != address(0)) {
                uint256 tokenPrice = getIncentivePrice(staleDataToleranceInSeconds, pricing, rewardToken);

                // skip processing if the token is worthless or unregistered
                if (tokenPrice == 0) continue;

                uint256 periodFinish = stats.periodFinishForRewards[i];
                uint256 rewardRate = stats.annualizedRewardAmounts[i];
                uint256 rewardDivisor = 10 ** IERC20Metadata(rewardToken).decimals();

                if (direction == IAutopoolStrategy.RebalanceDirection.Out) {
                    // if the destination has credits then extend the periodFinish by the expiredTolerance
                    // this allows destinations that consistently had rewards some leniency
                    if (hasCredits) {
                        periodFinish += EXPIRED_REWARD_TOLERANCE;
                    }

                    // slither-disable-next-line timestamp
                    if (periodFinish > block.timestamp) {
                        // tokenPrice is 1e18 and we want 1e18 out, so divide by the token decimals
                        totalRewards += rewardRate * tokenPrice / rewardDivisor;
                    }
                } else {
                    // when adding to a destination, count incentives only when either of the following conditions are
                    // met:
                    // 1) the incentive lasts at least 3 days
                    // 2) the incentive are allowed 2 expired days when dest has a positive incentive credit balance
                    if (
                        // slither-disable-next-line timestamp
                        periodFinish >= block.timestamp + 3 days
                            || (hasCredits && periodFinish + 2 days > block.timestamp)
                    ) {
                        // tokenPrice is 1e18 and we want 1e18 out, so divide by the token decimals
                        totalRewards += rewardRate * tokenPrice / rewardDivisor;
                    }
                }
            }
        }

        if (totalRewards == 0) {
            return 0;
        }

        uint256 lpTokenDivisor = 10 ** IDestinationVault(destAddress).decimals();
        uint256 totalSupplyInEth = 0;
        // When comparing in & out destinations, we want to consider the supply with our allocation
        // included to estimate the resulting incentive rate
        if (direction == IAutopoolStrategy.RebalanceDirection.Out) {
            totalSupplyInEth = stats.safeTotalSupply * lpPrice / lpTokenDivisor;
        } else {
            totalSupplyInEth = (stats.safeTotalSupply + lpAmountToAddOrRemove) * lpPrice / lpTokenDivisor;
        }

        // Adjust for totalSupplyInEth is 0
        if (totalSupplyInEth != 0) {
            return (totalRewards * 1e18) / totalSupplyInEth;
        } else {
            return (totalRewards);
        }
    }

    function getIncentivePrice(
        uint40 staleDataToleranceInSeconds,
        IIncentivesPricingStats pricing,
        address token
    ) public view returns (uint256) {
        (uint256 fastPrice, uint256 slowPrice) = pricing.getPriceOrZero(token, staleDataToleranceInSeconds);
        return fastPrice.min(slowPrice);
    }
}
