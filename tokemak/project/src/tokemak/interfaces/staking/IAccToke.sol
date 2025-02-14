// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IAccToke {
    ///////////////////////////////////////////////////////////////////
    //                        Variables
    ///////////////////////////////////////////////////////////////////

    function startEpoch() external view returns (uint256);
    function minStakeDuration() external view returns (uint256);

    struct Lockup {
        uint128 amount;
        uint128 end;
        uint256 points;
    }

    function getLockups(
        address user
    ) external view returns (Lockup[] memory);
    function toke() external view returns (IERC20Metadata);

    ///////////////////////////////////////////////////////////////////
    //                        Errors
    ///////////////////////////////////////////////////////////////////

    error ZeroAddress();
    error StakingDurationTooShort();
    error StakingDurationTooLong();
    error StakingPointsExceeded();
    error IncorrectStakingAmount();
    error InsufficientFunds();
    error LockupDoesNotExist();
    error NotUnlockableYet();
    error AlreadyUnlocked();
    error ExtendDurationTooShort();
    error TransfersDisabled();
    error TransferFailed();
    error NoRewardsToClaim();
    error InsufficientAmount();
    error InvalidLockupIds();
    error InvalidDurationLength();
    error InvalidMinStakeDuration();
    error AdminUnlockActive();

    ///////////////////////////////////////////////////////////////////
    //                        Events
    ///////////////////////////////////////////////////////////////////
    event SetMaxStakeDuration(uint256 oldDuration, uint256 newDuration);
    event Stake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Unstake(address indexed user, uint256 lockupId, uint256 amount, uint256 end, uint256 points);
    event Extend(
        address indexed user,
        uint256 lockupId,
        uint256 amount,
        uint256 oldEnd,
        uint256 newEnd,
        uint256 oldPoints,
        uint256 newPoints
    );
    event RewardsAdded(uint256 amount, uint256 accRewardPerShare);
    event RewardsCollected(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed recipient, uint256 amount);
    event AdminUnlockSet(bool newUnlockState);

    ///////////////////////////////////////////////////////////////////
    //
    //                        Staking Methods
    //
    ///////////////////////////////////////////////////////////////////

    /**
     * @notice Stake TOKE to an address that may not be the same as the sender of the funds. This can be used to give
     * staked funds to someone else.
     *
     * If staking before the start of staking (epoch), then the lockup start and end dates are shifted forward so that
     * the lockup starts at the epoch.
     *
     * @param amount TOKE to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     */
    function stake(uint256 amount, uint256 duration, address to) external;

    /**
     * @notice Stake TOKE
     *
     * If staking before the start of staking (epoch), then the lockup start and end dates are shifted forward so that
     * the lockup starts at the epoch.
     *
     * @notice Stake TOKE for myself.
     * @param amount TOKE to lockup in the stake
     * @param duration in seconds for the stake
     */
    function stake(uint256 amount, uint256 duration) external;

    /**
     * @notice Collect staked TOKE for a lockup and any earned rewards.
     * @param lockupIds the id of the lockup to unstake
     */
    function unstake(
        uint256[] memory lockupIds
    ) external;

    /**
     * @notice Collect staked TOKE for a lockup and any earned rewards.
     * @param lockupIds the id of the lockup to unstake
     * @param user address of the user to unstake for
     * @param to address to receive the unstaked TOKE
     */
    function unstake(uint256[] memory lockupIds, address user, address to) external;

    /**
     * @notice Extend a stake lockup for additional points.
     *
     * The stake end time is computed from the current time + duration, just like it is for new stakes. So a new stake
     * for seven days duration and an old stake extended with a seven days duration would have the same end.
     *
     * If an extend is made before the start of staking, the start time for the new stake is shifted forwards to the
     * start of staking, which also shifts forward the end date.
     *
     * @param lockupIds the id of the old lockup to extend
     * @param durations number of seconds from now to stake for
     */
    function extend(uint256[] memory lockupIds, uint256[] memory durations) external;

    ///////////////////////////////////////////////////////////////////
    //
    //                        Rewards
    //
    ///////////////////////////////////////////////////////////////////

    /// @notice The total amount of rewards earned for all stakes
    function totalRewardsEarned() external returns (uint256);

    /// @notice Total rewards claimed by all stakers
    function totalRewardsClaimed() external returns (uint256);

    /// @notice Rewards claimed by a specific wallet
    /// @param user Address of the wallet to check
    function rewardsClaimed(
        address user
    ) external returns (uint256);

    /**
     * @notice Calculate points based on duration from the staking system's start epoch to the user's staking end date
     *
     * @param amount TOKE to be staked
     * @param duration number of seconds to stake for
     * @return points staking points that would be returned
     * @return end staking period end date
     */
    function previewPoints(uint256 amount, uint256 duration) external view returns (uint256, uint256);

    /// @notice Preview the reward amount a caller can claim
    function previewRewards() external view returns (uint256);

    /// @notice Preview the reward amount a specified wallet can claim
    function previewRewards(
        address user
    ) external view returns (uint256);

    /// @notice Claim rewards for the caller
    function collectRewards() external returns (uint256);

    /// @notice Claim rewards for the user and send to recipient
    function collectRewards(address user, address recipient) external returns (uint256);

    /// @notice Check if amount can be staked
    function isStakeableAmount(
        uint256 amount
    ) external pure returns (bool);
}
