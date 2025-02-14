// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IBaseRewardPool } from "src/tokemak/interfaces/external/convex/IBaseRewardPool.sol";
import { IConvexBooster } from "src/tokemak/interfaces/external/convex/IConvexBooster.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";

library ConvexStaking {
    event DeployLiquidity(address lpToken, address staking, uint256 poolId, uint256 amount);
    event WithdrawLiquidity(address lpToken, address staking, uint256 amount);

    error withdrawStakeFailed();
    error DepositAndStakeFailed();
    error PoolIdLpTokenMismatch();
    error PoolIdStakingMismatch();
    error PoolShutdown();

    error MustBeMoreThanZero();
    error ArraysLengthMismatch();
    error BalanceMustIncrease();
    error MinLpAmountNotReached();
    error LpTokenAmountMismatch();
    error NoNonZeroAmountProvided();
    error InvalidBalanceChange();
    error InvalidAddress(address);

    /**
     * @notice Deposits and stakes Curve LP tokens to Convex
     * @dev Calls to external contract
     * @param booster Convex Booster address
     * @param lpToken Curve LP token to deposit
     * @param staking Convex reward contract associated with the Curve LP token
     * @param poolId Convex poolId for the associated Curve LP token
     * @param amount Quantity of Curve LP token to deposit and stake
     */
    function depositAndStake(
        IConvexBooster booster,
        address lpToken,
        address staking,
        uint256 poolId,
        uint256 amount
    ) public {
        if (address(booster) == address(0)) revert InvalidAddress(address(booster));
        if (lpToken == address(0)) revert InvalidAddress(address(lpToken));
        if (staking == address(0)) revert InvalidAddress(address(staking));
        if (amount == 0) revert MustBeMoreThanZero();

        emit DeployLiquidity(lpToken, staking, poolId, amount);

        _validatePoolInfo(booster, poolId, lpToken, staking);

        LibAdapter._approve(IERC20(lpToken), address(booster), amount);

        IBaseRewardPool rewards = IBaseRewardPool(staking);
        uint256 rewardsBeforeBalance = rewards.balanceOf(address(this));

        _runDeposit(booster, poolId, amount);

        if (rewards.balanceOf(address(this)) - rewardsBeforeBalance != amount) {
            revert BalanceMustIncrease();
        }
    }

    /**
     * @notice Withdraws a Curve LP token from Convex
     * @dev Does not claim available rewards
     * @dev Calls to external contract
     * @param lpToken Curve LP token to withdraw
     * @param staking Convex reward contract associated with the Curve LP token
     * @param amount Quantity of Curve LP token to withdraw
     */
    function withdrawStake(address lpToken, address staking, uint256 amount) public {
        // slither-disable-start incorrect-equality
        if (lpToken == address(0)) revert InvalidAddress(lpToken);
        if (staking == address(0)) revert InvalidAddress(staking);
        if (amount == 0) revert MustBeMoreThanZero();
        // slither-disable-end incorrect-equality

        IERC20 lpTokenErc = IERC20(lpToken);
        uint256 beforeLpBalance = lpTokenErc.balanceOf(address(this));

        IBaseRewardPool rewards = IBaseRewardPool(staking);

        emit WithdrawLiquidity(lpToken, staking, amount);

        bool success = rewards.withdrawAndUnwrap(amount, false);
        if (!success) revert withdrawStakeFailed();

        uint256 updatedLpBalance = lpTokenErc.balanceOf(address(this));
        if (updatedLpBalance - beforeLpBalance != amount) {
            revert BalanceMustIncrease();
        }
    }

    /// @dev Separate function to avoid stack-too-deep errors
    function _runDeposit(IConvexBooster booster, uint256 poolId, uint256 amount) private {
        bool success = booster.deposit(poolId, amount, true);
        if (!success) revert DepositAndStakeFailed();
    }

    /// @dev Separate function to avoid stack-too-deep errors
    function _validatePoolInfo(IConvexBooster booster, uint256 poolId, address lpToken, address staking) private view {
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (address poolLpToken,,, address crvRewards,, bool shutdown) = booster.poolInfo(poolId);
        if (lpToken != poolLpToken) revert PoolIdLpTokenMismatch();
        if (staking != crvRewards) revert PoolIdStakingMismatch();
        if (shutdown) revert PoolShutdown();
    }
}
