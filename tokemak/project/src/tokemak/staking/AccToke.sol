// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable not-rely-on-time,no-complex-fallback

import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { ERC20Votes } from "openzeppelin-contracts/token/ERC20/extensions/ERC20Votes.sol";
import { ERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { Pausable } from "openzeppelin-contracts/security/Pausable.sol";
import { SafeCast } from "openzeppelin-contracts/utils/math/SafeCast.sol";

import { PRBMathUD60x18 } from "prb-math/contracts/PRBMathUD60x18.sol";

import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { IAccToke } from "src/tokemak/interfaces/staking/IAccToke.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract AccToke is IAccToke, ERC20Votes, Pausable, SystemComponent, SecurityBase {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IWETH9;

    // variables
    uint256 public immutable startEpoch;
    uint256 public immutable minStakeDuration;
    // solhint-disable-next-line const-name-snakecase
    uint256 public maxStakeDuration = 1461 days; // default 4 years
    uint256 public constant MIN_STAKE_AMOUNT = 10_000;
    uint256 public constant MAX_STAKE_AMOUNT = 100e6 * 1e18; // default 100m toke
    uint256 public constant MAX_POINTS = type(uint192).max;

    mapping(address => Lockup[]) public lockups;

    uint256 private constant YEAR_BASE_BOOST = 18e17;
    uint256 private constant MIN_STAKE_DURATION = 1 days;
    IERC20Metadata public immutable toke;

    //
    // Reward Vars
    //
    IWETH9 private immutable weth;

    uint256 public constant REWARD_FACTOR = 1e12;

    // tracks user's checkpointed reward debt per share
    mapping(address => uint256) public rewardDebtPerShare;
    // keeps track of rewards checkpointed / offloaded but not yet transferred
    mapping(address => uint256) private unclaimedRewards;
    // total current accumulated reward per share
    uint256 public accRewardPerShare;

    // See {IAccToke-totalRewardsEarned}
    uint256 public totalRewardsEarned;
    // See {IAccToke-totalRewardsClaimed}
    uint256 public totalRewardsClaimed;
    // See {IAccToke-rewardsClaimed}
    mapping(address => uint256) public rewardsClaimed;

    /// @notice If true, users will be able to withdraw before locks end
    bool public adminUnlock;

    /// @notice In the event of an admin unlock, some functions should not run.  This protects those functions
    modifier whenNoAdminUnlock() {
        if (adminUnlock) revert AdminUnlockActive();
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        uint256 _startEpoch,
        uint256 _minStakeDuration
    )
        SystemComponent(_systemRegistry)
        ERC20("Staked Toke", "accToke")
        ERC20Permit("accToke")
        SecurityBase(address(_systemRegistry.accessController()))
    {
        if (_minStakeDuration < MIN_STAKE_DURATION) revert InvalidMinStakeDuration();

        startEpoch = _startEpoch;
        minStakeDuration = _minStakeDuration;

        toke = systemRegistry.toke();
        weth = systemRegistry.weth();
    }

    // @dev short-circuit transfers
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    // @dev short-circuit transfers
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    /// @inheritdoc IAccToke
    function stake(uint256 amount, uint256 duration, address to) external {
        _stake(amount, duration, to);
    }

    /// @inheritdoc IAccToke
    function stake(uint256 amount, uint256 duration) external {
        _stake(amount, duration, msg.sender);
    }

    /// @inheritdoc IAccToke
    function isStakeableAmount(
        uint256 amount
    ) public pure returns (bool) {
        return amount >= MIN_STAKE_AMOUNT && amount <= MAX_STAKE_AMOUNT;
    }

    function _stake(uint256 amount, uint256 duration, address to) internal whenNotPaused whenNoAdminUnlock {
        //
        // validation checks
        //
        if (to == address(0)) revert ZeroAddress();
        if (!isStakeableAmount(amount)) revert IncorrectStakingAmount();

        // duration checked inside previewPoints
        (uint256 points, uint256 end) = previewPoints(amount, duration);

        _maxPointsCheck(points);

        // checkpoint rewards for caller
        _collectRewards(to, to, false);

        // save information for current lockup
        lockups[to].push(Lockup({ amount: SafeCast.toUint128(amount), end: SafeCast.toUint128(end), points: points }));

        // create points for user
        _mint(to, points);

        emit Stake(to, lockups[to].length - 1, amount, end, points);

        // transfer staked toke in
        toke.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IAccToke
    function unstake(
        uint256[] memory lockupIds
    ) external override {
        unstake(lockupIds, msg.sender, msg.sender);
    }

    function unstake(uint256[] memory lockupIds, address user, address to) public override whenNotPaused {
        Errors.verifyNotZero(user, "user");
        Errors.verifyNotZero(to, "to");

        if (msg.sender != user && msg.sender != address(systemRegistry.autoPoolRouter())) {
            revert Errors.AccessDenied();
        }

        _collectRewards(user, user, false);

        uint256 length = lockupIds.length;
        if (length == 0) revert InvalidLockupIds();

        uint256 totalPoints = 0;
        uint256 totalAmount = 0;

        uint256 totalLockups = lockups[user].length;
        for (uint256 iter = 0; iter < length;) {
            uint256 lockupId = lockupIds[iter];
            if (lockupId >= totalLockups) revert LockupDoesNotExist();

            // get staking information
            Lockup memory lockup = lockups[user][lockupId];

            if (lockup.end == 0) revert AlreadyUnlocked();

            // If admin unlock is false, make sure lock endtime has been reached
            if (!adminUnlock) {
                // slither-disable-next-line timestamp
                if (block.timestamp < lockup.end) revert NotUnlockableYet();
            } else {
                // If adminUnlock is true, update lock end locally.  Allows for actual unlock time in event
                lockup.end = uint128(block.timestamp);
            }

            // remove stake
            delete lockups[user][lockupId];

            // tally total points to be burned
            totalPoints += lockup.points;

            emit Unstake(user, lockupId, lockup.amount, lockup.end, lockup.points);

            // tally total toke amount to be returned
            totalAmount += lockup.amount;

            unchecked {
                ++iter;
            }
        }

        // wipe points
        _burn(user, totalPoints);
        // send staked toke back to user
        toke.safeTransfer(to, totalAmount);
    }

    /// @inheritdoc IAccToke
    //slither-disable-start timestamp
    function extend(uint256[] memory lockupIds, uint256[] memory durations) external whenNotPaused whenNoAdminUnlock {
        uint256 length = lockupIds.length;
        if (length == 0) revert InvalidLockupIds();
        if (length != durations.length) revert InvalidDurationLength();

        // before doing anything, make sure the rewards checkpoints are updated!
        _collectRewards(msg.sender, msg.sender, false);

        uint256 totalExtendedPoints = 0;

        uint256 totalLockups = lockups[msg.sender].length;
        for (uint256 iter = 0; iter < length;) {
            uint256 lockupId = lockupIds[iter];
            uint256 duration = durations[iter];
            if (lockupId >= totalLockups) revert LockupDoesNotExist();

            // duration checked inside previewPoints
            Lockup storage lockup = lockups[msg.sender][lockupId];
            uint256 oldAmount = lockup.amount;
            uint256 oldEnd = lockup.end;
            uint256 oldPoints = lockup.points;

            // Can only extend ongoing lockups
            Errors.verifyNotZero(oldEnd, "oldEnd");

            (uint256 newPoints, uint256 newEnd) = previewPoints(oldAmount, duration);

            if (newEnd <= oldEnd) revert ExtendDurationTooShort();
            lockup.end = SafeCast.toUint128(newEnd);
            lockup.points = newPoints;
            totalExtendedPoints = totalExtendedPoints + newPoints - oldPoints;

            emit Extend(msg.sender, lockupId, oldAmount, oldEnd, newEnd, oldPoints, newPoints);

            unchecked {
                ++iter;
            }
        }

        _maxPointsCheck(totalExtendedPoints);

        // issue extra points for extension
        _mint(msg.sender, totalExtendedPoints);
    }
    //slither-disable-end timestamp

    /// @inheritdoc IAccToke
    function previewPoints(uint256 amount, uint256 duration) public view returns (uint256 points, uint256 end) {
        if (duration < minStakeDuration) revert StakingDurationTooShort();
        if (duration > maxStakeDuration) revert StakingDurationTooLong();

        // slither-disable-next-line timestamp
        uint256 start = block.timestamp > startEpoch ? block.timestamp : startEpoch;
        end = start + duration;

        // calculate points based on duration from staking end date
        uint256 endYearpoc = ((end - startEpoch) * 1e18) / 365 days;
        uint256 multiplier = PRBMathUD60x18.pow(YEAR_BASE_BOOST, endYearpoc);

        points = (amount * multiplier) / 1e18;
    }

    /// @inheritdoc IAccToke
    function getLockups(
        address user
    ) external view returns (Lockup[] memory) {
        return lockups[user];
    }

    /// @notice Update max stake duration allowed
    function setMaxStakeDuration(
        uint256 _maxStakeDuration
    ) external hasRole(Roles.ACC_TOKE_MANAGER) {
        uint256 old = maxStakeDuration;

        maxStakeDuration = _maxStakeDuration;

        emit SetMaxStakeDuration(old, _maxStakeDuration);
    }

    /// @notice Set `adminUnlock` boolean to true
    /// @dev Can only be done once
    /// @dev If this is true, users will be able to withdraw their stake without reaching the end of locks
    function setAdminUnlock() external hasRole(Roles.ACC_TOKE_MANAGER) {
        // Revert if flag has been flipped
        if (adminUnlock) revert Errors.AlreadySet("adminUnlock");

        adminUnlock = true;

        emit AdminUnlockSet(true);
    }

    function pause() external hasRole(Roles.ACC_TOKE_MANAGER) {
        _pause();
    }

    function unpause() external hasRole(Roles.ACC_TOKE_MANAGER) {
        _unpause();
    }

    /* **************************************************************************** */
    /*																				*/
    /* 									Rewards										*/
    /*																				*/
    /* **************************************************************************** */

    /// @notice Allows an actor to deposit ETH as staking reward to be distributed to all staked participants
    /// @param amount Amount of `WETH` to take from caller and deposit as reward for the stakers
    function addWETHRewards(
        uint256 amount
    ) external {
        // update accounting to factor in new rewards
        _addWETHRewards(amount);
        // actually transfer WETH
        weth.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev Internal function used by both `addWETHRewards` external and the `receive()` function
    /// @param amount See {IAccToke-addWETHRewards}.
    function _addWETHRewards(
        uint256 amount
    ) internal whenNotPaused {
        Errors.verifyNotZero(amount, "amount");

        uint256 supply = totalSupply();
        Errors.verifyNotZero(supply, "supply");

        // slither-disable-next-line timestamp
        if (amount * REWARD_FACTOR < supply) {
            revert InsufficientAmount();
        }

        totalRewardsEarned += amount;
        accRewardPerShare += amount * REWARD_FACTOR / supply;

        emit RewardsAdded(amount, accRewardPerShare);
    }

    /// @inheritdoc IAccToke
    function previewRewards() external view returns (uint256 amount) {
        return previewRewards(msg.sender);
    }

    /// @inheritdoc IAccToke
    function previewRewards(
        address user
    ) public view returns (uint256 amount) {
        uint256 supply = totalSupply();
        // slither-disable-next-line incorrect-equality,timestamp
        if (supply == 0) {
            return unclaimedRewards[user];
        }

        // calculate reward per share by taking the current reward per share and subtracting what user already claimed
        uint256 _netRewardsPerShare = accRewardPerShare - rewardDebtPerShare[user];

        // calculate full reward user is entitled to by taking their recently earned and adding unclaimed checkpointed
        return ((balanceOf(user) * _netRewardsPerShare) / REWARD_FACTOR) + unclaimedRewards[user];
    }

    /// @inheritdoc IAccToke
    function collectRewards() external override returns (uint256) {
        return _collectRewards(msg.sender, msg.sender, true);
    }

    /// @inheritdoc IAccToke
    function collectRewards(address user, address recipient) external override returns (uint256) {
        address router = address(systemRegistry.autoPoolRouter());
        if (msg.sender != user && msg.sender != router) {
            revert Errors.AccessDenied();
        }

        Errors.verifyNotZero(recipient, "recipient");

        return _collectRewards(user, recipient, true);
    }

    /// @dev See {IAccToke-collectRewards}.
    function _collectRewards(address user, address recipient, bool distribute) internal returns (uint256) {
        // calculate user's new rewards per share (current minus claimed)
        uint256 netRewardsPerShare = accRewardPerShare - rewardDebtPerShare[user];
        // calculate amount of actual rewards
        uint256 netRewards = (balanceOf(user) * netRewardsPerShare) / REWARD_FACTOR;
        // get reference to user's pending (sandboxed) rewards
        uint256 pendingRewards = unclaimedRewards[user];

        // update checkpoint to current
        rewardDebtPerShare[user] = accRewardPerShare;

        // if nothing to claim, bail
        // slither-disable-next-line incorrect-equality,timestamp
        if (netRewards == 0 && pendingRewards == 0) {
            return 0;
        }

        if (distribute) {
            //
            // if asked for actual distribution, transfer all earnings
            //

            // reset sandboxed rewards
            unclaimedRewards[user] = 0;

            // get total amount by adding new rewards and previously sandboxed
            uint256 totalClaiming = netRewards + pendingRewards;

            // update running totals
            //slither-disable-next-line costly-loop
            totalRewardsClaimed += totalClaiming;
            rewardsClaimed[user] += totalClaiming;

            emit RewardsClaimed(user, recipient, totalClaiming);

            // send rewards to recipient
            weth.safeTransfer(recipient, totalClaiming);

            // return total amount claimed
            return totalClaiming;
        }

        // slither-disable-next-line timestamp
        if (netRewards > 0) {
            // Save (sandbox) to their account for later transfer
            unclaimedRewards[user] += netRewards;

            emit RewardsCollected(user, netRewards);
        }

        // nothing collected
        return 0;
    }

    function _maxPointsCheck(
        uint256 points
    ) private view {
        // slither-disable-next-line timestamp
        if (points + totalSupply() > MAX_POINTS) {
            revert StakingPointsExceeded();
        }
    }

    /// @notice Catch-all. If any eth is sent, wrap and add to rewards
    receive() external payable {
        // update accounting to factor in new rewards
        // NOTE: doing it in this order keeps slither happy
        _addWETHRewards(msg.value);
        // appreciate the ETH! wrap and add as rewards
        weth.deposit{ value: msg.value }();
    }
}
