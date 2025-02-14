// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ICurveStableSwapNG } from "src/tokemak/interfaces/external/curve/ICurveStableSwapNG.sol";
import { ICryptoSwapPool, IPool } from "src/tokemak/interfaces/external/curve/ICryptoSwapPool.sol";
import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

//slither-disable-start similar-names
library CurveV2FactoryCryptoAdapter {
    event WithdrawLiquidity(
        uint256[] amountsWithdrawn,
        address[] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress
    );

    function removeLiquidity(
        uint256[] memory amounts,
        uint256 maxLpBurnAmount,
        address poolAddress,
        address lpTokenAddress,
        IWETH9 weth
    ) public returns (address[] memory, uint256[] memory) {
        return removeLiquidity(amounts, maxLpBurnAmount, poolAddress, lpTokenAddress, weth, false);
    }

    /**
     * @notice Withdraw liquidity from Curve pool
     *  @dev Calls to external contract
     *  @dev We trust sender to send a true Curve poolAddress.
     *       If it's not the case it will fail in the remove_liquidity_one_coin part
     *  @param amounts Minimum amounts of coin to receive
     *  @param maxLpBurnAmount Amount of LP tokens to burn in the withdrawal
     *  @param poolAddress Curve pool address
     *  @param lpTokenAddress LP token of the pool to burn
     *  @param weth WETH address on the operating chain
     *  @param isNg is a newer ng pool with dynamic arrays
     *  @return tokens Addresses of the withdrawn tokens
     *  @return actualAmounts Amounts of the withdrawn tokens
     */
    function removeLiquidity(
        uint256[] memory amounts,
        uint256 maxLpBurnAmount,
        address poolAddress,
        address lpTokenAddress,
        IWETH9 weth,
        bool isNg
    ) public returns (address[] memory tokens, uint256[] memory actualAmounts) {
        //slither-disable-start reentrancy-events
        if (amounts.length > 4) {
            revert Errors.InvalidParam("amounts");
        }
        Errors.verifyNotZero(maxLpBurnAmount, "maxLpBurnAmount");
        Errors.verifyNotZero(poolAddress, "poolAddress");
        Errors.verifyNotZero(lpTokenAddress, "lpTokenAddress");
        Errors.verifyNotZero(address(weth), "weth");

        uint256[] memory coinsBalancesBefore = new uint256[](amounts.length);
        tokens = new address[](amounts.length);
        uint256 ethIndex = 999;
        for (uint256 i = 0; i < amounts.length; ++i) {
            address coin = IPool(poolAddress).coins(i);
            tokens[i] = coin;

            if (coin == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
                coinsBalancesBefore[i] = address(this).balance;
                ethIndex = i;
            } else {
                tokens[i] = coin;
                coinsBalancesBefore[i] = IERC20(coin).balanceOf(address(this));
            }
        }
        uint256 lpTokenBalanceBefore = IERC20(lpTokenAddress).balanceOf(address(this));

        _runWithdrawal(poolAddress, amounts, maxLpBurnAmount, isNg);

        uint256 lpTokenBalanceAfter = IERC20(lpTokenAddress).balanceOf(address(this));
        uint256 lpTokenAmount = lpTokenBalanceBefore - lpTokenBalanceAfter;
        if (lpTokenAmount > maxLpBurnAmount) {
            revert LibAdapter.LpTokenAmountMismatch();
        }
        actualAmounts = _compareCoinsBalances(
            coinsBalancesBefore, _getCoinsBalances(tokens, weth, ethIndex != 999 ? true : false), amounts, false
        );

        if (ethIndex != 999) {
            // Wrapping up received ETH as system operates with WETH
            // slither-disable-next-line arbitrary-send-eth
            weth.deposit{ value: actualAmounts[ethIndex] }();
        }

        _updateWethAddress(tokens, address(weth));

        emit WithdrawLiquidity(
            actualAmounts,
            tokens,
            [lpTokenAmount, lpTokenBalanceAfter, IERC20(lpTokenAddress).totalSupply()],
            poolAddress
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @dev This is a helper function to replace Curve's Registry pointer
     * to ETH with WETH address to be compatible with the rest of the system
     */
    function _updateWethAddress(address[] memory tokens, address weth) private pure {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
                tokens[i] = weth;
            }
        }
    }

    /// @dev Gets balances of pool's ERC-20 tokens or ETH
    function _getCoinsBalances(
        address[] memory tokens,
        IWETH9 weth,
        bool useEth
    ) private view returns (uint256[] memory coinsBalances) {
        uint256 nTokens = tokens.length;
        coinsBalances = new uint256[](nTokens);

        for (uint256 i = 0; i < nTokens; ++i) {
            address coin = tokens[i];
            if (coin == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
                coinsBalances[i] = useEth ? address(this).balance : weth.balanceOf(address(this));
            } else {
                coinsBalances[i] = IERC20(coin).balanceOf(address(this));
            }
        }
    }

    /// @dev Validate to have a valid balance change
    function _compareCoinsBalances(
        uint256[] memory balancesBefore,
        uint256[] memory balancesAfter,
        uint256[] memory amounts,
        bool isLiqDeployment
    ) private pure returns (uint256[] memory balanceChange) {
        uint256 nTokens = amounts.length;
        balanceChange = new uint256[](nTokens);

        for (uint256 i = 0; i < nTokens; ++i) {
            uint256 balanceDiff =
                isLiqDeployment ? balancesBefore[i] - balancesAfter[i] : balancesAfter[i] - balancesBefore[i];

            if (balanceDiff < amounts[i]) {
                revert LibAdapter.InvalidBalanceChange();
            }
            balanceChange[i] = balanceDiff;
        }
    }

    function _runWithdrawal(
        address poolAddress,
        uint256[] memory amounts,
        uint256 maxLpBurnAmount,
        bool isNg
    ) private {
        if (isNg) {
            ICurveStableSwapNG pool = ICurveStableSwapNG(poolAddress);

            // slither-disable-next-line unused-return
            pool.remove_liquidity(maxLpBurnAmount, amounts);
        } else {
            uint256 nTokens = amounts.length;
            ICryptoSwapPool pool = ICryptoSwapPool(poolAddress);
            if (nTokens == 2) {
                uint256[2] memory staticParamArray = [amounts[0], amounts[1]];
                pool.remove_liquidity(maxLpBurnAmount, staticParamArray);
            } else if (nTokens == 3) {
                uint256[3] memory staticParamArray = [amounts[0], amounts[1], amounts[2]];
                pool.remove_liquidity(maxLpBurnAmount, staticParamArray);
            } else if (nTokens == 4) {
                uint256[4] memory staticParamArray = [amounts[0], amounts[1], amounts[2], amounts[3]];
                pool.remove_liquidity(maxLpBurnAmount, staticParamArray);
            }
        }
    }

    //slither-disable-end similar-names
}
