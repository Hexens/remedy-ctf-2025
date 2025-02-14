// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IAerodromeGauge } from "src/tokemak/interfaces/external/aerodrome/IAerodromeGauge.sol";

import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

library AerodromeStakingAdapter {
    event DeployLiquidity(
        uint256 amountDeposited,
        address stakingToken,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pool,
        address gaugeAddress
    );

    event WithdrawLiquidity(
        uint256 amountsWithdrawn,
        address stakingToken,
        // 0 - lpMintAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pool,
        address gaugeAddress
    );

    error MinLpAmountNotReached();
    error LpTokenAmountMismatch();

    /**
     * @notice Stakes tokens to Aerodrome
     * @dev Calls to external contract
     * @param gaugeAddress Address of Aerodrome gauge
     * @param amount number of LP tokens to stake.  Doubles as min amount as gauge should mint 1:1
     */
    function stakeLPs(address gaugeAddress, uint256 amount) public {
        Errors.verifyNotZero(gaugeAddress, "gaugeAddress");
        Errors.verifyNotZero(amount, "amount");
        //slither-disable-start reentrancy-events

        IAerodromeGauge gauge = IAerodromeGauge(gaugeAddress);

        uint256 lpTokensBefore = gauge.balanceOf(address(this));

        address stakingToken = gauge.stakingToken();
        Errors.verifyNotZero(stakingToken, "stakingToken");

        LibAdapter._approve(IERC20(stakingToken), address(gauge), amount);

        gauge.deposit(amount);

        uint256 lpTokensAfter = gauge.balanceOf(address(this));
        uint256 lpTokenAmount = lpTokensAfter - lpTokensBefore;
        if (lpTokenAmount < amount) revert MinLpAmountNotReached();

        emit DeployLiquidity(
            amount, stakingToken, [lpTokenAmount, lpTokensAfter, gauge.totalSupply()], stakingToken, address(gauge)
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice Unstakes tokens from Aerodrome
     * @dev Calls to external contract
     * @param gaugeAddress Address of Aerodrome gauge
     * @param amount number of corresponding LP token to withdraw
     */
    function unstakeLPs(address gaugeAddress, uint256 amount) public {
        Errors.verifyNotZero(gaugeAddress, "gaugeAddress");
        Errors.verifyNotZero(amount, "amount");
        //slither-disable-start reentrancy-events

        IAerodromeGauge gauge = IAerodromeGauge(gaugeAddress);

        address stakingToken = gauge.stakingToken();
        Errors.verifyNotZero(stakingToken, "stakingToken");

        uint256 lpTokensBefore = gauge.balanceOf(address(this));

        gauge.withdraw(amount);

        uint256 lpTokensAfter = gauge.balanceOf(address(this));

        uint256 lpTokenAmount = lpTokensBefore - lpTokensAfter;
        if (lpTokenAmount > amount) revert LpTokenAmountMismatch();

        emit WithdrawLiquidity(
            amount, stakingToken, [lpTokenAmount, lpTokensAfter, gauge.totalSupply()], stakingToken, address(gauge)
        );
        //slither-disable-end reentrancy-events
    }
}
