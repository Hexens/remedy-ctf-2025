// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IRouter } from "src/tokemak/interfaces/external/aerodrome/IRouter.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

library AerodromeAdapter {
    event WithdrawLiquidity(
        uint256[2] amountsWithdrawn,
        address[2] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address pairAddress
    );

    /**
     * @notice A struct used to pass Aerodrome params
     * @dev Used to avoid stack-too-deep-errors
     * @param router Aerodrome Router contract
     * @param tokens tokens to withdraw
     * @param amounts min quantity of tokens to withdraw
     * @param pool Aerodrome pool address
     * @param stable A flag that indicates pool type
     * @param maxLpBurnAmount max amount of LP tokens to burn for withdrawal
     */
    struct AerodromeRemoveLiquidityParams {
        address router;
        address[] tokens;
        uint256[] amounts;
        address pool;
        bool stable;
        uint256 maxLpBurnAmount;
    }

    /**
     * @notice Withdraws liquidity from Aerodrome
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param params AerodromeRemoveLiquidityParams struct with all the required params
     * @return actualAmounts Amounts of tokens received
     */
    //slither-disable-start timestamp reentrancy-events
    function removeLiquidity(
        AerodromeRemoveLiquidityParams memory params
    ) external returns (uint256[] memory) {
        Errors.verifyNotZero(params.router, "router");
        Errors.verifyNotZero(params.maxLpBurnAmount, "maxLpBurnAmount");
        Errors.verifyNotZero(params.tokens[0], "tokens[0]");
        Errors.verifyNotZero(params.tokens[1], "tokens[1]");
        Errors.verifyNotZero(params.pool, "pool");

        if (params.tokens.length != 2) revert Errors.InvalidParam("tokens.length");
        if (params.amounts.length != 2) revert Errors.InvalidParam("amounts.length");

        LibAdapter._approve(IERC20(params.pool), address(params.router), params.maxLpBurnAmount);

        // slither-disable-next-line similar-names
        (uint256[] memory actualAmounts, uint256 lpTokenBurnAmount) = _runWithdrawal(params);

        if (lpTokenBurnAmount > params.maxLpBurnAmount) {
            revert LibAdapter.LpTokenAmountMismatch();
        }
        if (actualAmounts[0] < params.amounts[0]) revert LibAdapter.InvalidBalanceChange();
        if (actualAmounts[1] < params.amounts[1]) revert LibAdapter.InvalidBalanceChange();

        // slither-disable-next-line reentrancy-events
        emit WithdrawLiquidity(
            [actualAmounts[0], actualAmounts[1]],
            [params.tokens[0], params.tokens[1]],
            [lpTokenBurnAmount, IERC20(params.pool).balanceOf(address(this)), IERC20(params.pool).totalSupply()],
            address(params.pool)
        );

        return actualAmounts;
    }
    //slither-disable-end timestamp reentrancy-events

    ///@dev This is a helper function to avoid stack-too-deep-errors
    function _runWithdrawal(
        AerodromeRemoveLiquidityParams memory _params
    ) internal returns (uint256[] memory actualAmounts, uint256 lpBurnAmount) {
        uint256 lpTokensBefore = IERC20(_params.pool).balanceOf(address(this));
        (uint256 amountA, uint256 amountB) = IRouter(_params.router).removeLiquidity(
            _params.tokens[0],
            _params.tokens[1],
            _params.stable,
            _params.maxLpBurnAmount,
            _params.amounts[0],
            _params.amounts[1],
            address(this),
            block.timestamp
        );

        uint256 lpTokensAfter = IERC20(_params.pool).balanceOf(address(this));

        lpBurnAmount = lpTokensBefore - lpTokensAfter;

        actualAmounts = new uint256[](2);
        actualAmounts[0] = amountA;
        actualAmounts[1] = amountB;
    }
}
