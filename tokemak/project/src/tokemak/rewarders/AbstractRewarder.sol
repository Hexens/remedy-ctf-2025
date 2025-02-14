// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "openzeppelin-contracts/utils/Address.sol";

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";

import { IBaseRewarder } from "src/tokemak/interfaces/rewarders/IBaseRewarder.sol";

import { IAccToke } from "src/tokemak/interfaces/staking/IAccToke.sol";

import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

/**
 * @dev An abstract contract that serves as the base for rewarder contracts.
 * It implements common functionalities for reward distribution, including calculating rewards per token,
 * tracking user rewards, and handling stake-related operations.
 * Inherited by rewarder contracts, such as MainRewarder and ExtraRewarder.
 * The contract is inspired by the Convex contract but uses block-based duration instead of timestamp-based duration.
 */
abstract contract AbstractRewarder is IBaseRewarder, SecurityBase {
    using SafeERC20 for IERC20;

    /// @notice The minimum duration for recovering tokens (1 year).
    uint256 public constant MINIMUM_RECOVER_DURATION = 31_536_000;

    /// @notice The duration of the reward period in blocks.
    uint256 public immutable durationInBlock;

    ///  @notice It is used to determine if the new rewards should be distributed immediately or queued for later. If
    /// the ratio of current rewards to the sum of new and queued rewards is less than newRewardRatio, the new rewards
    /// are distributed immediately; otherwise, they are added to the queue.
    uint256 public immutable newRewardRatio;

    /// @notice An instance of the system registry contract.
    ISystemRegistry internal immutable systemRegistry;

    /// @notice The address of the token to be distributed as rewards.
    address public immutable rewardToken;

    /// @notice The block number when the current reward period ends.
    uint256 public periodInBlockFinish;

    /// @notice The rate of reward distribution per block.
    uint256 public rewardRate;

    /// @notice The block number when rewards were last updated.
    uint256 public lastUpdateBlock;

    /// @notice The amount of rewards distributed per staked token stored.
    uint256 public rewardPerTokenStored;

    /// @notice The amount of rewards waiting in the queue to be distributed.
    uint256 public queuedRewards;

    /// @notice The amount of current rewards being distributed.
    uint256 public currentRewards;

    /// @notice The total amount of rewards distributed historically.
    uint256 public historicalRewards;

    /// @notice The amount of reward per token paid to each user.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice The amount of rewards for each user.
    mapping(address => uint256) public rewards;

    /// @notice The duration for locking the Toke token rewards.
    uint256 public tokeLockDuration;

    /// @notice Whitelisted addresses for queuing new rewards.
    mapping(address => bool) public whitelistedAddresses;

    /// @notice Role that manages rewarder contract.
    bytes32 internal immutable rewardRole;

    /**
     * @param _systemRegistry Address of the system registry.
     * @param _rewardToken Address of the reward token.
     * @param _newRewardRatio The new reward rate.
     * @param _durationInBlock The duration of the reward period in blocks.
     * @param _rewardRole Role that controls role based functions in Rewarder.
     */
    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bytes32 _rewardRole
    ) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(_rewardToken, "_rewardToken");
        Errors.verifyNotZero(_durationInBlock, "_durationInBlock");
        Errors.verifyNotZero(_newRewardRatio, "_newRewardRatio");
        Errors.verifyNotZero(_rewardRole, "_rewardRole");

        systemRegistry = _systemRegistry;
        if (!systemRegistry.isRewardToken(_rewardToken)) {
            revert Errors.InvalidParam("_rewardToken");
        }
        rewardToken = _rewardToken;
        newRewardRatio = _newRewardRatio;
        durationInBlock = _durationInBlock;
        rewardRole = _rewardRole;
    }

    /// @notice Restricts access to whitelisted addresses or holders of the liquidator role.
    modifier onlyWhitelisted() {
        if (!whitelistedAddresses[msg.sender] && !_hasRole(Roles.LIQUIDATOR_MANAGER, msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    /**
     * @notice Internal function that updates the user's rewards.
     * @param account The address of the user to update the rewards for.
     */
    function _updateReward(
        address account
    ) internal {
        uint256 earnedRewards = 0;
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlock = lastBlockRewardApplicable();

        if (rewardPerTokenStored > 0) {
            if (account != address(0)) {
                earnedRewards = earned(account);
                rewards[account] = earnedRewards;
                userRewardPerTokenPaid[account] = rewardPerTokenStored;
            }
        }

        emit UserRewardUpdated(account, earnedRewards, rewardPerTokenStored, lastUpdateBlock);
    }

    /// @inheritdoc IBaseRewarder
    function lastBlockRewardApplicable() public view returns (uint256) {
        return block.number < periodInBlockFinish ? block.number : periodInBlockFinish;
    }

    /// @inheritdoc IBaseRewarder
    function rewardPerToken() public view returns (uint256) {
        uint256 total = totalSupply();
        if (total == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + ((lastBlockRewardApplicable() - lastUpdateBlock) * rewardRate * 1e18 / total);
    }

    /**
     * @inheritdoc IBaseRewarder
     * @dev
     * The function calculates the earned rewards based on the balance of the account,
     * the total supply of the staked tokens, the rewards per token and the last reward rate
     * the user has been paid at. The reward rate is determined by the `rewardPerToken`
     * function and is a measure of the amount of rewards distributed per staked token
     * per block.
     *
     * The amount of earned rewards is calculated as follows:
     * - First, it calculates the difference between the current reward per token and
     *   the last reward rate the user was paid at, which gives the reward rate per token
     *   since the user last claimed rewards.
     * - This difference is multiplied by the balance of the account to find the total
     *   amount of rewards the account has earned since it last claimed rewards.
     * - Finally, the function adds the rewards that have not yet been claimed by the
     *   user to find the total amount of earned rewards.
     */
    function earned(
        address account
    ) public view returns (uint256) {
        return (balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    /**
     * @inheritdoc IBaseRewarder
     * @dev The function transfers the new rewards from the caller to this contract,
     *      ensuring that the deposited amount matches the declared rewards.
     *      Irrespective of whether we're near the start or the end of a reward period, if the accrued rewards
     *      are too large relative to the new rewards (i.e., queuedRatio is greater than newRewardRatio), the new
     *      rewards will be added to the queue rather than being immediately distributed.
     */
    function queueNewRewards(
        uint256 newRewards
    ) external onlyWhitelisted {
        uint256 startingQueuedRewards = queuedRewards;
        uint256 startingNewRewards = newRewards;

        newRewards += startingQueuedRewards;

        if (block.number >= periodInBlockFinish) {
            notifyRewardAmount(newRewards);
            queuedRewards = 0;
        } else {
            uint256 elapsedBlock = block.number - (periodInBlockFinish - durationInBlock);
            uint256 currentAtNow = rewardRate * elapsedBlock;
            uint256 queuedRatio = currentAtNow * 1000 / newRewards;

            if (queuedRatio < newRewardRatio) {
                notifyRewardAmount(newRewards);
                queuedRewards = 0;
            } else {
                queuedRewards = newRewards;
            }
        }

        emit QueuedRewardsUpdated(startingQueuedRewards, startingNewRewards, queuedRewards);

        // Transfer the new rewards from the caller to this contract.
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), startingNewRewards);
    }

    /**
     * @notice Notifies the contract about the amount of reward tokens to be distributed.
     * @param reward The amount of reward tokens to be distributed.
     * @dev The function updates the rewardRate, lastUpdateBlock, periodInBlockFinish, and historicalRewards.
     *      It calculates the remaining reward based on the current block number and adjusts the reward rate
     *      accordingly.
     *
     *      If the current block number is within the reward period, the remaining reward is added to the reward queue
     *      and will be distributed gradually over the remaining duration.
     *      If the current block number exceeds the reward period, the remaining reward is distributed immediately.
     */
    function notifyRewardAmount(
        uint256 reward
    ) internal {
        historicalRewards += reward;

        // Correctly calculate leftover reward when totalSupply() is 0.
        if (totalSupply() == 0) {
            if (lastUpdateBlock < periodInBlockFinish) {
                // slither-disable-next-line divide-before-multiply
                reward += (periodInBlockFinish - lastUpdateBlock) * rewardRate;
            }
        } else if (block.number < periodInBlockFinish) {
            uint256 remaining = periodInBlockFinish - block.number;

            // slither-disable-next-line divide-before-multiply
            uint256 leftover = remaining * rewardRate;
            reward += leftover;
        }

        _updateReward(address(0));

        // slither-disable-next-line divide-before-multiply
        rewardRate = reward / durationInBlock;
        // If `reward` < `durationInBlock`, it will result in a `rewardRate` of 0, which we want to prevent.
        if (rewardRate <= 0) revert Errors.ZeroAmount();

        currentRewards = reward;
        lastUpdateBlock = block.number;
        periodInBlockFinish = block.number + durationInBlock;

        emit RewardAdded(reward, rewardRate, lastUpdateBlock, periodInBlockFinish, historicalRewards);
    }

    /**
     * inheritdoc IBaseRewarder
     * @dev If the lock duration is set to 0, it turns off the staking functionality for Toke tokens.
     * @dev If the lock duration is greater than 0, it should be long enough to satisfy the minimum staking duration
     * requirement of the accToke contract.
     */
    function setTokeLockDuration(
        uint256 _tokeLockDuration
    ) external hasRole(rewardRole) {
        // if duration is not set to 0 (that would turn off functionality), make sure it's long enough for accToke
        if (_tokeLockDuration > 0) {
            Errors.verifyNotZero(address(systemRegistry.accToke()), "accToke");
            if (_tokeLockDuration < systemRegistry.accToke().minStakeDuration()) {
                revert IAccToke.StakingDurationTooShort();
            }
        }

        tokeLockDuration = _tokeLockDuration;
        emit TokeLockDurationUpdated(_tokeLockDuration);
    }

    /// @inheritdoc IBaseRewarder
    function addToWhitelist(
        address wallet
    ) external override hasRole(rewardRole) {
        Errors.verifyNotZero(wallet, "wallet");
        if (whitelistedAddresses[wallet]) {
            revert Errors.ItemExists();
        }
        whitelistedAddresses[wallet] = true;

        emit AddedToWhitelist(wallet);
    }

    /// @inheritdoc IBaseRewarder
    function removeFromWhitelist(
        address wallet
    ) external override hasRole(rewardRole) {
        if (!whitelistedAddresses[wallet]) {
            revert Errors.ItemNotFound();
        }

        whitelistedAddresses[wallet] = false;

        emit RemovedFromWhitelist(wallet);
    }

    /// @inheritdoc IBaseRewarder
    function isWhitelisted(
        address wallet
    ) external view override returns (bool) {
        return whitelistedAddresses[wallet];
    }

    /**
     * @notice Internal function to distribute rewards to a specific account.
     * @param account The address of the user to distribute rewards to.
     * @param recipient The address to send the rewards to.
     */
    function _getReward(address account, address recipient) internal {
        Errors.verifyNotZero(account, "account");
        Errors.verifyNotZero(recipient, "recipient");

        uint256 reward = earned(account);
        (IAccToke accToke, address tokeAddress) = (systemRegistry.accToke(), address(systemRegistry.toke()));

        // slither-disable-next-line incorrect-equality
        if (reward == 0) return;

        // if NOT toke, or staking is turned off (by duration = 0), just send reward back
        if (rewardToken != tokeAddress || tokeLockDuration == 0) {
            rewards[account] = 0;
            emit RewardPaid(account, recipient, reward);

            IERC20(rewardToken).safeTransfer(recipient, reward);
        } else if (accToke.isStakeableAmount(reward)) {
            rewards[account] = 0;
            emit RewardPaid(account, recipient, reward);
            // authorize accToke to get our reward Toke
            LibAdapter._approve(IERC20(tokeAddress), address(accToke), reward);

            // stake Toke
            accToke.stake(reward, tokeLockDuration, recipient);
        }
    }

    /**
     * @notice Internal function to handle withdrawals.
     * @param account The address of the user to handle withdrawal.
     * @dev This function primarily checks for valid parameters and emits an event.
     *      It adopts a pattern established by Convex. It helps with:
     *      - Identifying system errors (if a revert happens here, there is an issue within our system).
     *      - Enhancing system monitoring capabilities through emitted events.
     * @param amount The amount to be withdrawn.
     */
    function _withdrawAbstractRewarder(address account, uint256 amount) internal {
        Errors.verifyNotZero(account, "account");
        Errors.verifyNotZero(amount, "amount");

        emit Withdrawn(account, amount);
    }

    /**
     * @notice Internal function to handle staking.
     * @dev This function primarily checks for valid parameters and emits an event.
     *      It adopts a pattern established by Convex. It helps with:
     *      - Identifying system errors (if a revert happens here, there is an issue within our system).
     *      - Enhancing system monitoring capabilities through emitted events.
     * @param account The address of the user to handle staking.
     * @param amount The amount to be staked.
     */
    function _stakeAbstractRewarder(address account, uint256 amount) internal {
        Errors.verifyNotZero(account, "account");
        Errors.verifyNotZero(amount, "amount");

        emit Staked(account, amount);
    }

    /// @inheritdoc IBaseRewarder
    function totalSupply() public view virtual returns (uint256);

    /// @inheritdoc IBaseRewarder
    function recover(address token, address recipient) external override hasRole(Roles.TOKEN_RECOVERY_MANAGER) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(recipient, "recipient");
        if (recipient == address(this)) revert Errors.InvalidAddress(recipient);

        if (!canTokenBeRecovered(token)) revert Errors.AssetNotAllowed(token);
        if (block.number < lastUpdateBlock + MINIMUM_RECOVER_DURATION && token == rewardToken) {
            revert RecoverDurationPending();
        }

        if (token == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
            uint256 tokenBalance = address(this).balance;
            if (tokenBalance > 0) {
                emit Recovered(token, recipient, tokenBalance);
                Address.sendValue(payable(recipient), tokenBalance);
            }
        } else {
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance > 0) {
                emit Recovered(token, recipient, tokenBalance);
                IERC20(token).safeTransfer(recipient, tokenBalance);
            }
        }
    }

    /**
     * @notice Check if a token is recoverable.
     * @param token The address to be checked.
     * @return bool indicating if the token is recoverable.
     */
    function canTokenBeRecovered(
        address token
    ) public view virtual returns (bool);

    /// @inheritdoc IBaseRewarder
    function balanceOf(
        address account
    ) public view virtual returns (uint256);
}
