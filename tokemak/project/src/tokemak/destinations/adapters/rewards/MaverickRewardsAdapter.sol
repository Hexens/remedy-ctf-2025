// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IReward } from "src/tokemak/interfaces/external/maverick/IReward.sol";
import { RewardAdapter } from "src/tokemak/destinations/adapters/rewards/RewardAdapter.sol";

//slither-disable-next-line missing-inheritance
library MaverickRewardsAdapter {
    /// @notice Claim rewards for Maverick Boosted Position LP tokens staked in their rewarder
    /// @param rewarder the Maverick rewarder contract
    /// @return amounts the amount of each token that was claimed
    /// @return tokens the tokens that were claimed
    function claimRewards(
        address rewarder
    ) public returns (uint256[] memory, address[] memory) {
        return _claimRewards(rewarder, address(this));
    }

    /// @notice Claim rewards for Maverick Boosted Position LP tokens staked in their rewarder
    /// @param rewarder the Maverick rewarder contract
    /// @param sendTo the destination of the rewarded tokens
    /// @return amounts the amount of each token that was claimed
    /// @return tokens the tokens that were claimed
    function claimRewards(address rewarder, address sendTo) public returns (uint256[] memory, address[] memory) {
        return _claimRewards(rewarder, sendTo);
    }

    /// @notice Claim rewards for Maverick Boosted Position LP tokens staked in their rewarder
    /// @param rewarder the Maverick rewarder contract
    /// @param sendTo the destination of the rewarded tokens
    /// @return amounts the amount of each token that was claimed
    /// @return tokens the tokens that were claimed
    function _claimRewards(address rewarder, address sendTo) internal returns (uint256[] memory, address[] memory) {
        Errors.verifyNotZero(rewarder, "rewarder");
        address account = address(this);

        IReward reward = IReward(rewarder);

        // Fetching the earned rewards information
        IReward.EarnedInfo[] memory earnedInfos = reward.earned(account);
        uint256 length = earnedInfos.length;

        address[] memory rewardTokens = new address[](length);
        uint256[] memory amountsClaimed = new uint256[](length);

        // Iterating over each reward info, if earned is not zero, reward is claimed
        for (uint8 i = 0; i < length; ++i) {
            IReward.EarnedInfo memory earnedInfo = earnedInfos[i];
            IERC20 rewardToken = IERC20(earnedInfo.rewardToken);
            rewardTokens[i] = address(rewardToken);

            if (earnedInfo.earned == 0) {
                amountsClaimed[i] = 0;
                continue;
            }

            // Fetching the current balance before claiming the reward
            uint256 balanceBefore = rewardToken.balanceOf(sendTo);

            // Claiming the reward
            // slither-disable-next-line unused-return
            reward.getReward(sendTo, i);

            // Calculating the claimed amount by comparing the balance after claiming the reward
            amountsClaimed[i] = rewardToken.balanceOf(sendTo) - balanceBefore;
        }

        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);

        return (amountsClaimed, rewardTokens);
    }
}
