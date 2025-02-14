// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IBaseRewarder {
    error RecoverDurationPending();

    event RewardAdded(
        uint256 reward,
        uint256 rewardRate,
        uint256 lastUpdateBlock,
        uint256 periodInBlockFinish,
        uint256 historicalRewards
    );
    event UserRewardUpdated(
        address indexed user, uint256 amount, uint256 rewardPerTokenStored, uint256 lastUpdateBlock
    );
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed recipient, uint256 reward);
    event QueuedRewardsUpdated(uint256 startingQueuedRewards, uint256 startingNewRewards, uint256 queuedRewards);
    event AddedToWhitelist(address indexed wallet);
    event RemovedFromWhitelist(address indexed wallet);

    event TokeLockDurationUpdated(uint256 newDuration);

    event Recovered(address token, address recipient, uint256 amount);

    /**
     * @notice Claims and transfers all rewards for the specified account
     */
    function getReward() external;

    /**
     * @notice Stakes the specified amount of tokens for the specified account.
     * @param account The address of the account to stake tokens for.
     * @param amount The amount of tokens to stake.
     */
    function stake(address account, uint256 amount) external;

    /**
     * @notice Calculate the earned rewards for an account.
     * @param account Address of the account.
     * @return The earned rewards for the given account.
     */
    function earned(
        address account
    ) external view returns (uint256);

    /**
     * @notice Calculates the rewards per token for the current block.
     * @dev The total amount of rewards available in the system is fixed, and it needs to be distributed among the users
     * based on their token balances and staking duration.
     * Rewards per token represent the amount of rewards that each token is entitled to receive at the current block.
     * The calculation takes into account the reward rate, the time duration since the last update,
     * and the total supply of tokens in the staking pool.
     * @return The updated rewards per token value for the current block.
     */
    function rewardPerToken() external view returns (uint256);

    /**
     * @notice Get the current reward rate per block.
     * @return The current reward rate per block.
     */
    function rewardRate() external view returns (uint256);

    /**
     * @notice Get the current TOKE lock duration.
     * @return The current TOKE lock duration.
     */
    function tokeLockDuration() external view returns (uint256);

    /**
     * @notice Get the last block where rewards are applicable.
     * @return The last block number where rewards are applicable.
     */
    function lastBlockRewardApplicable() external view returns (uint256);

    /**
     * @notice The total amount of tokens staked
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice The amount of tokens staked for the specified account
     * @param account The address of the account to get the balance of
     */
    function balanceOf(
        address account
    ) external view returns (uint256);

    /**
     * @notice Queue new rewards to be distributed.
     * @param newRewards The amount of new rewards to be queued.
     */
    function queueNewRewards(
        uint256 newRewards
    ) external;

    /**
     * @notice Token distributed as rewards
     * @return reward token address
     */
    function rewardToken() external view returns (address);

    /**
     * @notice Add an address to the whitelist.
     * @param wallet The address to be added to the whitelist.
     */
    function addToWhitelist(
        address wallet
    ) external;

    /**
     * @notice Remove an address from the whitelist.
     * @param wallet The address to be removed from the whitelist.
     */
    function removeFromWhitelist(
        address wallet
    ) external;

    /**
     * @notice Recovers tokens from the rewarder. However, a recovery duration of 1 year is applicable for reward token
     * @param token Address of token
     * @param recipient recipient Address of recipient
     */
    function recover(address token, address recipient) external;

    /**
     * @notice Check if an address is whitelisted.
     * @param wallet The address to be checked.
     * @return bool indicating if the address is whitelisted.
     */
    function isWhitelisted(
        address wallet
    ) external view returns (bool);
}
