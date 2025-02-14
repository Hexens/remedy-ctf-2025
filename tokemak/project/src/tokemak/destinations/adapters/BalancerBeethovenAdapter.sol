// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/tokemak/interfaces/external/balancer/IBalancerPool.sol";
import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

library BalancerBeethovenAdapter {
    event WithdrawLiquidity(
        uint256[] amountsWithdrawn,
        address[] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress,
        bytes32 poolId
    );

    error ArraysLengthMismatch();
    error BalanceMustIncrease();
    error NoNonZeroAmountProvided();
    error InvalidBalanceChange();

    ///@dev For StablePool and MetaStablePool
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    ///@dev For ComposableStablePool
    enum ExitKindComposable {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT,
        EXACT_BPT_IN_FOR_ALL_TOKENS_OUT
    }

    /**
     * @param pool address of Balancer Pool
     * @param bptAmount uint256 pool token amount expected back
     * @param tokens IERC20[] of tokens to be withdrawn from pool
     * @param amountsOut uint256[] min amount of tokens expected on withdrawal
     * @param userData bytes data, used for info about kind of pool exit
     */
    struct WithdrawParams {
        address pool;
        uint256 bptAmount;
        address[] tokens;
        uint256[] amountsOut;
        bytes userData;
    }

    /**
     * @notice Withdraw liquidity from Balancer or Beethoven pool
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to withdrawn liquidity from
     * @param tokens Addresses of tokens to withdraw. Should match pool tokens
     * @param exactAmountsOut Array of exact amounts of tokens to be withdrawn from pool
     * @param maxLpBurnAmount Max amount of LP tokens to burn in the withdrawal
     */
    function removeLiquidityImbalance(
        IVault vault,
        address pool,
        address[] calldata tokens,
        uint256[] calldata exactAmountsOut,
        uint256 maxLpBurnAmount
    ) public returns (uint256[] memory actualAmounts) {
        bytes memory userData = BalancerUtilities.isComposablePool(pool)
            ? abi.encode(
                ExitKindComposable.BPT_IN_FOR_EXACT_TOKENS_OUT, _getUserAmounts(pool, exactAmountsOut), maxLpBurnAmount
            )
            : abi.encode(ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, exactAmountsOut, maxLpBurnAmount);

        // Verify if at least one non-zero amount is present
        bool hasNonZeroAmount = false;
        uint256 nTokens = exactAmountsOut.length;
        for (uint256 i = 0; i < nTokens; ++i) {
            if (exactAmountsOut[i] != 0) {
                hasNonZeroAmount = true;
                break;
            }
        }
        if (!hasNonZeroAmount) {
            revert NoNonZeroAmountProvided();
        }

        actualAmounts = _withdraw(
            vault,
            WithdrawParams({
                pool: pool,
                bptAmount: maxLpBurnAmount,
                tokens: tokens,
                amountsOut: exactAmountsOut,
                userData: userData
            })
        );
    }

    /**
     * @notice Withdraw liquidity from Balancer V2 pool (specifying exact LP tokens to burn)
     * @dev Calls into external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param vault Balancer Vault contract
     * @param pool Balancer or Beethoven Pool to liquidity withdrawn from
     * @param exactLpBurnAmount Amount of LP tokens to burn in the withdrawal
     * @param minAmountsOut Array of minimum amounts of tokens to be withdrawn from pool
     */
    function removeLiquidity(
        IVault vault,
        address pool,
        address[] memory tokens,
        uint256[] memory minAmountsOut,
        uint256 exactLpBurnAmount
    ) public returns (uint256[] memory withdrawnAmounts) {
        bytes memory userData = BalancerUtilities.isComposablePool(pool)
            ? abi.encode(ExitKindComposable.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, exactLpBurnAmount)
            : abi.encode(ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, exactLpBurnAmount);

        withdrawnAmounts = _withdraw(
            vault,
            WithdrawParams({
                pool: pool,
                bptAmount: exactLpBurnAmount,
                tokens: tokens,
                amountsOut: minAmountsOut,
                userData: userData
            })
        );
    }

    /// @dev Helper method to avoid stack-too-deep-errors
    function _withdraw(IVault vault, WithdrawParams memory params) private returns (uint256[] memory amountsOut) {
        //slither-disable-start reentrancy-events

        address pool = params.pool;
        IBalancerPool poolInterface = IBalancerPool(pool);

        Errors.verifyNotZero(address(vault), "vault");
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(params.bptAmount, "params.bptAmount");

        amountsOut = params.amountsOut;
        address[] memory tokens = params.tokens;

        uint256 nTokens = tokens.length;
        // slither-disable-next-line incorrect-equality
        if (nTokens == 0 || nTokens != amountsOut.length) {
            revert ArraysLengthMismatch();
        }

        bytes32 poolId = poolInterface.getPoolId();
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory poolTokens,,) = vault.getPoolTokens(poolId);

        if (poolTokens.length != nTokens) {
            revert ArraysLengthMismatch();
        }

        // Record balance before withdraw
        uint256 bptBalanceBefore = poolInterface.balanceOf(address(this));

        uint256[] memory assetBalancesBefore = new uint256[](nTokens);
        for (uint256 i = 0; i < nTokens; ++i) {
            assetBalancesBefore[i] = poolTokens[i].balanceOf(address(this));
        }

        // As we're exiting the pool we need to make an ExitPoolRequest instead
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: amountsOut,
            userData: params.userData,
            toInternalBalance: false
        });
        vault.exitPool(
            poolId,
            address(this), // sender,
            payable(address(this)), // recipient,
            request
        );

        // Make sure we burned BPT, and assets were received
        uint256 bptBalanceAfter = poolInterface.balanceOf(address(this));
        if (bptBalanceAfter >= bptBalanceBefore) {
            revert InvalidBalanceChange();
        }

        for (uint256 i = 0; i < nTokens; ++i) {
            uint256 assetBalanceBefore = assetBalancesBefore[i];

            IERC20 currentToken = poolTokens[i];
            if (address(currentToken) != pool) {
                uint256 currentBalance = currentToken.balanceOf(address(this));

                if (currentBalance < assetBalanceBefore + amountsOut[i]) {
                    revert BalanceMustIncrease();
                }
                // Get actual amount returned for event, reuse amountsOut array
                amountsOut[i] = currentBalance - assetBalanceBefore;
            }
        }
        emit WithdrawLiquidity(
            amountsOut,
            tokens,
            [bptBalanceBefore - bptBalanceAfter, bptBalanceAfter, poolInterface.totalSupply()],
            pool,
            poolId
        );
        //slither-disable-end reentrancy-events
    }

    /**
     * @notice We should exclude BPT amount from amounts array for userData in ComposablePools
     * @param pool Balancer or Beethoven pool address
     * @param amountsOut array of pool token amounts that length-equal with IVault#getPoolTokens array
     */
    function _getUserAmounts(
        address pool,
        uint256[] memory amountsOut
    ) private view returns (uint256[] memory amountsUser) {
        if (BalancerUtilities.isComposablePool(pool)) {
            uint256 uix = 0;
            uint256 bptIndex = IBalancerComposableStablePool(pool).getBptIndex();
            uint256 nTokens = amountsOut.length;
            amountsUser = new uint256[](nTokens - 1);
            for (uint256 i = 0; i < nTokens; i++) {
                if (i != bptIndex) {
                    amountsUser[uix] = amountsOut[i];
                    uix++;
                }
            }
        } else {
            amountsUser = amountsOut;
        }
    }
}
