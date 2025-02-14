// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IReward } from "src/tokemak/interfaces/external/maverick/IReward.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

library MaverickStakingAdapter {
    event DeployLiquidity(
        address stakingToken,
        // 0 - lpStakeAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address rewarder
    );

    event WithdrawLiquidity(
        address stakingToken,
        // 0 - lpUnstakeAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address rewarder
    );

    error InvalidBalanceChange();

    /**
     * @notice Stakes tokens from Maverick Reward contract
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param rewarder Maverick Reward contract
     * @param amount quantity of staking token to deposit
     */
    function stakeLPs(IReward rewarder, uint256 amount) public {
        //slither-disable-start reentrancy-events
        Errors.verifyNotZero(address(rewarder), "rewarder");
        Errors.verifyNotZero(amount, "amount");

        uint256 lpTokensBefore = rewarder.balanceOf(address(this));

        address stakingToken = rewarder.stakingToken();
        LibAdapter._approve(IERC20(stakingToken), address(rewarder), amount);
        rewarder.stake(amount, address(this));

        uint256 lpTokensAfter = rewarder.balanceOf(address(this));
        if (lpTokensAfter - lpTokensBefore != amount) revert InvalidBalanceChange();

        emit DeployLiquidity(
            stakingToken, [amount, lpTokensAfter, IERC20(stakingToken).totalSupply()], address(rewarder)
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice Unstakes tokens from Maverick Reward contract
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param rewarder Maverick Reward contract
     * @param amount quantity of staking token to deposit
     */
    function unstakeLPs(IReward rewarder, uint256 amount) public {
        //slither-disable-start reentrancy-events
        Errors.verifyNotZero(address(rewarder), "rewarder");
        Errors.verifyNotZero(amount, "amount");

        uint256 lpTokensBefore = rewarder.balanceOf(address(this));

        address stakingToken = rewarder.stakingToken();
        rewarder.unstake(amount, address(this));

        uint256 lpTokensAfter = rewarder.balanceOf(address(this));
        if (lpTokensBefore - lpTokensAfter != amount) revert InvalidBalanceChange();

        emit WithdrawLiquidity(
            stakingToken, [amount, lpTokensAfter, IERC20(stakingToken).totalSupply()], address(rewarder)
        );
        //slither-disable-end reentrancy-events
    }
}
