// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { MainRewarder, ISystemRegistry, Errors } from "src/tokemak/rewarders/MainRewarder.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

/**
 * @title DestinationVaultMainRewarder
 * @notice Main rewarder for Destination Vault contracts.  This is used to enforce role based
 *      access control and stake tracker functionality for Destination Vault rewarders.
 */
contract DestinationVaultMainRewarder is MainRewarder {
    // slither-disable-start similar-names,missing-zero-check
    address public immutable stakeTracker;

    constructor(
        ISystemRegistry _systemRegistry,
        address _stakeTracker,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bool _allowExtraReward
    )
        MainRewarder(
            _systemRegistry,
            _rewardToken,
            _newRewardRatio,
            _durationInBlock,
            Roles.DV_REWARD_MANAGER,
            _allowExtraReward
        )
    {
        Errors.verifyNotZero(_stakeTracker, "_stakeTracker");
        stakeTracker = _stakeTracker;
    }
    // slither-disable-end similar-names,missing-zero-check

    /// @notice Restricts access to the stake tracker only.
    modifier onlyStakeTracker() {
        if (msg.sender != stakeTracker) {
            revert Errors.AccessDenied();
        }
        _;
    }

    /**
     * @notice Used to stake via DV contracts.
     * @param account Account to stake for.
     * @param amount Amount to stake.
     */
    function stake(address account, uint256 amount) public onlyStakeTracker {
        _stake(account, amount);
    }

    /**
     * @notice Used to withdraw via DV contracts.
     * @param account Account to withdraw for.
     * @param amount Amount to withdraw.
     * @param claim Whether or not to claim.
     */
    function withdraw(address account, uint256 amount, bool claim) public onlyStakeTracker {
        _withdraw(account, amount, claim);
    }

    /**
     * @notice Used to claim rewards via stakeTracker.
     * @dev This function is not actually used by the DV contracts, this function is implemented to lock reward
     *      claiming.
     * @param account Account to claim rewards for.
     * @param recipient Address to send rewards to.
     * @param claimExtras Whether or not to claim extra rewards.
     */
    function getReward(address account, address recipient, bool claimExtras) public {
        if (msg.sender != account) {
            revert Errors.AccessDenied();
        }

        _getReward(account, recipient, claimExtras);
    }

    function canTokenBeRecovered(
        address
    ) public pure override returns (bool) {
        return true;
    }
}
