// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";
import { RewardAdapter } from "src/tokemak/destinations/adapters/rewards/RewardAdapter.sol";
import { ILiquidityGaugeV2 } from "src/tokemak/interfaces/external/curve/ILiquidityGaugeV2.sol";

library CurveRewardsAdapter {
    // solhint-disable-next-line var-name-mixedcase
    uint256 private constant MAX_REWARDS = 8;

    /**
     * @notice Gets all rewards from the reward pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param gauge The gauge to claim rewards from
     * @return amountsClaimed Quantity of reward tokens
     * @return rewardTokens Addresses of claimed reward tokens
     */
    function claimRewards(
        address gauge
    ) public returns (uint256[] memory amountsClaimed, address[] memory rewardTokens) {
        Errors.verifyNotZero(gauge, "gauge");

        ILiquidityGaugeV2 rewardPool = ILiquidityGaugeV2(gauge);

        IERC20[] memory tempRewardTokens = new IERC20[](MAX_REWARDS);
        uint256 rewardsLength = 0;

        // Curve Pool don't have a method to get the reward tokens length
        // so we need to iterate until we get a zero address.
        // All Curve pools have MAX_REWARDS set to 8
        // https://etherscan.deth.net/address/0x182b723a58739a9c974cfdb385ceadb237453c28
        for (uint256 i = 0; i < MAX_REWARDS; ++i) {
            address rewardToken = rewardPool.reward_tokens(i);
            if (rewardToken == address(0)) {
                break;
            }
            tempRewardTokens[i] = IERC20(rewardToken);
            ++rewardsLength;
        }

        // resize the tokens array to the correct size
        rewardTokens = new address[](rewardsLength);
        for (uint256 i = 0; i < rewardsLength; ++i) {
            rewardTokens[i] = address(tempRewardTokens[i]);
        }
        uint256[] memory balancesBefore = new uint256[](rewardsLength);
        amountsClaimed = new uint256[](rewardsLength);

        // get balances before
        address account = address(this);
        for (uint256 i = 0; i < rewardsLength; ++i) {
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(account);
        }
        // claim rewards
        rewardPool.claim_rewards(account);

        // get balances after and calculate amounts claimed
        for (uint256 i = 0; i < rewardsLength; ++i) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf(account);
            amountsClaimed[i] = balance - balancesBefore[i];
        }
        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);
    }
}
