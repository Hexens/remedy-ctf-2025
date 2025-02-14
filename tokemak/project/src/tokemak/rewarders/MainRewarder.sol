// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

import { IBaseRewarder } from "src/tokemak/interfaces/rewarders/IBaseRewarder.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IExtraRewarder } from "src/tokemak/interfaces/rewarders/IExtraRewarder.sol";
import { AbstractRewarder } from "src/tokemak/rewarders/AbstractRewarder.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";

/**
 * @title MainRewarder
 * @dev Contract is abstract to enforce proper role designation on construction
 * @notice The MainRewarder contract extends the AbstractRewarder and
 * manages the distribution of main rewards along with additional rewards
 * from ExtraRewarder contracts.
 */
abstract contract MainRewarder is AbstractRewarder, IMainRewarder, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Maximum amount of extra rewards addresses that can be registered
    uint256 public constant MAX_EXTRA_REWARDS = 15;

    /// @notice True if additional reward tokens/contracts are allowed to be added
    /// @dev Destination Vaults should not allow extras. Autopool's should.
    bool public immutable allowExtraRewards;

    /// @notice Extra rewards can be added, but not removed, ref: https://github.com/Tokemak/v2-core/issues/659
    EnumerableSet.AddressSet private _extraRewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bytes32 _rewardRole,
        bool _allowExtraRewards
    ) AbstractRewarder(_systemRegistry, _rewardToken, _newRewardRatio, _durationInBlock, _rewardRole) {
        // slither-disable-next-line missing-zero-check
        allowExtraRewards = _allowExtraRewards;
    }

    /// @inheritdoc IMainRewarder
    function extraRewardsLength() external view returns (uint256) {
        return _extraRewards.length();
    }

    /// @inheritdoc IMainRewarder
    function addExtraReward(
        address reward
    ) external hasRole(rewardRole) {
        if (!allowExtraRewards) {
            revert ExtraRewardsNotAllowed();
        }
        if (_extraRewards.length() >= MAX_EXTRA_REWARDS) {
            revert MaxExtraRewardsReached();
        }
        Errors.verifyNotZero(reward, "reward");

        if (!_extraRewards.add(reward)) {
            revert Errors.ItemExists();
        }

        emit ExtraRewardAdded(reward);
    }

    /// @inheritdoc IMainRewarder
    function getExtraRewarder(
        uint256 index
    ) external view returns (IExtraRewarder rewarder) {
        return IExtraRewarder(_extraRewards.at(index));
    }

    /// @inheritdoc IMainRewarder
    function extraRewards() external view returns (address[] memory) {
        return _extraRewards.values();
    }

    function _withdraw(address account, uint256 amount, bool claim) internal {
        _updateReward(account);
        _withdrawAbstractRewarder(account, amount);

        uint256 length = _extraRewards.length();
        for (uint256 i = 0; i < length; ++i) {
            // No need to worry about reentrancy here
            // slither-disable-next-line reentrancy-no-eth
            IExtraRewarder(_extraRewards.at(i)).withdraw(account, amount);
        }

        if (claim) {
            _processRewards(account, account, true);
        }

        // slither-disable-next-line events-maths
        _totalSupply -= amount;
        _balances[account] -= amount;
    }

    function _stake(address account, uint256 amount) internal {
        _updateReward(account);
        _stakeAbstractRewarder(account, amount);

        uint256 length = _extraRewards.length();
        for (uint256 i = 0; i < length; ++i) {
            // No need to worry about reentrancy here
            // slither-disable-next-line reentrancy-no-eth
            IExtraRewarder(_extraRewards.at(i)).stake(account, amount);
        }

        // slither-disable-next-line events-maths
        _totalSupply += amount;
        _balances[account] += amount;
    }

    /// @inheritdoc IBaseRewarder
    function getReward() external nonReentrant {
        _updateReward(msg.sender);
        _processRewards(msg.sender, msg.sender, true);
    }

    function _getReward(address account, address recipient, bool claimExtras) internal nonReentrant {
        _updateReward(account);
        _processRewards(account, recipient, claimExtras);
    }

    /// @inheritdoc IBaseRewarder
    function totalSupply() public view override(AbstractRewarder, IBaseRewarder) returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IBaseRewarder
    function balanceOf(
        address account
    ) public view override(AbstractRewarder, IBaseRewarder) returns (uint256) {
        return _balances[account];
    }

    function _processRewards(address account, address recipient, bool claimExtras) internal {
        _getReward(account, recipient);
        uint256 length = _extraRewards.length();

        //also get rewards from linked rewards
        if (claimExtras) {
            for (uint256 i = 0; i < length; ++i) {
                IExtraRewarder(_extraRewards.at(i)).getReward(account, recipient);
            }
        }
    }
}
