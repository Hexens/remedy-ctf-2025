// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { MainRewarder, ISystemRegistry, Errors } from "src/tokemak/rewarders/MainRewarder.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

/**
 * @title AutopoolMainRewarder
 * @notice Main rewarder for Autopool contracts.
 */
contract AutopoolMainRewarder is MainRewarder {
    using SafeERC20 for IERC20;

    /// @notice IERC20 instance of token being staked in rewarder.
    IERC20 public immutable stakingToken;

    // slither-disable-start similar-names
    constructor(
        ISystemRegistry _systemRegistry,
        address _rewardToken,
        uint256 _newRewardRatio,
        uint256 _durationInBlock,
        bool _allowExtraReward,
        address _stakingToken
    )
        MainRewarder(
            _systemRegistry,
            _rewardToken,
            _newRewardRatio,
            _durationInBlock,
            Roles.AUTO_POOL_REWARD_MANAGER,
            _allowExtraReward
        )
    {
        Errors.verifyNotZero(_stakingToken, "_stakingToken");

        stakingToken = IERC20(_stakingToken);
    }
    // slither-disable-end similar-names

    /**
     * @notice Withdraws autopilot vault token from rewarder.
     * @dev Balance updates, reward calculations taken care of in inherited contract.
     * @param account Account that is withdrawing assets.
     * @param amount Amount of assets to be withdrawn.
     * @param claim Whether or not to claim rewards.
     */
    function withdraw(address account, uint256 amount, bool claim) public {
        if (msg.sender != account && msg.sender != address(systemRegistry.autoPoolRouter())) {
            revert Errors.AccessDenied();
        }

        _withdraw(account, amount, claim);

        stakingToken.safeTransfer(account, amount);
    }

    /**
     * @notice Stakes autopilot vault token to rewarder.
     * @dev Balance updates, reward calculations taken care of in inherited contract.
     * @param account Account staking.
     * @param amount Amount of autopilot vault token to stake.
     */
    function stake(address account, uint256 amount) public {
        _stake(account, amount);

        // slither-disable-next-line arbitrary-send-erc20
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Gets reward for msg.sender.
     * @dev Used to enforce msg.sender check.
     * @param account Account to claim rewards for
     * @param recipient Address to send rewards to
     */
    function getReward(address account, address recipient, bool claimExtras) public {
        if (msg.sender != account && msg.sender != address(systemRegistry.autoPoolRouter())) {
            revert Errors.AccessDenied();
        }

        _getReward(account, recipient, claimExtras);
    }

    /**
     * @notice Checks if token can be recovered.
     * @dev staked token cant be recovered
     * @param token Token to check.
     * @return bool True if token can be recovered.
     */
    function canTokenBeRecovered(
        address token
    ) public view override returns (bool) {
        if (token == address(stakingToken)) {
            return false;
        }
        return true;
    }
}
