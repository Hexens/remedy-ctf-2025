// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable var-name-mixedcase
struct RewardType {
    address reward_token;
    uint128 reward_integral;
    uint128 reward_remaining;
}

interface IConvexRewardPool {
    /// @notice the address of the gauge
    function curveGauge() external view returns (address);

    /// @notice update and claim rewards from all locations
    function rewardLength() external view returns (uint256);

    /// @notice get the reward token address
    function rewards(
        uint256 i
    ) external view returns (RewardType memory);

    /// @notice claim reward for given account (unguarded)
    function getReward(
        address _account
    ) external;

    /// @notice convex pool id
    function convexPoolId() external view returns (uint256);

    /// @notice queue new rewards to the pool
    function queueNewRewards(
        uint256
    ) external;

    /// @notice the operator of the pool
    function operator() external view returns (address);

    /// @notice the period end time
    function periodFinish() external view returns (uint256);
}
