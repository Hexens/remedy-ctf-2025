// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IPool } from "src/tokemak/interfaces/external/maverick/IPool.sol";
import { IRouter } from "src/tokemak/interfaces/external/maverick/IRouter.sol";

//slither-disable-start similar-names
library MaverickAdapter {
    event WithdrawLiquidity(
        uint256[2] amountsWithdrawn,
        address[2] tokens,
        // 0 - lpBurnAmount
        // 1 - lpShare
        // 2 - lpTotalSupply
        uint256[3] lpAmounts,
        address poolAddress,
        uint256 receivingTokenId,
        uint256[] deployedBinIds
    );

    error MustBeMoreThanZero();
    error ArraysLengthMismatch();
    error LpTokenAmountMismatch();
    error NoNonZeroAmountProvided();
    error InvalidBalanceChange();

    struct MaverickWithdrawalExtraParams {
        address poolAddress;
        uint256 tokenId;
        uint256 deadline;
        IPool.RemoveLiquidityParams[] maverickParams;
    }

    /**
     * @notice Withdraws liquidity from Maverick
     * @dev Calls to external contract. Should be guarded with
     * non-reentrant flags in a used contract
     * @param router Maverick Router contract
     * @param amounts quantity of tokens to withdraw
     * @param maxLpBurnAmount max amount of LP tokens to burn for withdrawal
     * @param extraParams encoded `MaverickWithdrawalExtraParams`
     */
    function removeLiquidity(
        IRouter router,
        uint256[] calldata amounts,
        uint256 maxLpBurnAmount,
        bytes calldata extraParams
    ) external returns (uint256[] memory actualAmounts) {
        //slither-disable-start reentrancy-events
        if (maxLpBurnAmount == 0) revert MustBeMoreThanZero();
        if (amounts.length != 2) revert ArraysLengthMismatch();
        if (amounts[0] == 0 && amounts[1] == 0) revert NoNonZeroAmountProvided();

        (MaverickWithdrawalExtraParams memory maverickExtraParams) =
            abi.decode(extraParams, (MaverickWithdrawalExtraParams));

        router.position().approve(address(router), maverickExtraParams.tokenId);

        (uint256 tokenAAmount, uint256 tokenBAmount, IPool.BinDelta[] memory binDeltas) =
            _runWithdrawal(router, amounts, maverickExtraParams);

        // Collect deployed bins data
        (
            uint256 binslpAmountSummary,
            uint256 binslpBalanceSummary,
            uint256 binsLpTotalSupplySummary,
            uint256[] memory deployedBinIds
        ) = _collectBinSummary(binDeltas, IPool(maverickExtraParams.poolAddress), maverickExtraParams.tokenId);

        if (binslpAmountSummary > maxLpBurnAmount) revert LpTokenAmountMismatch();
        if (tokenAAmount < amounts[0]) revert InvalidBalanceChange();
        if (tokenBAmount < amounts[1]) revert InvalidBalanceChange();

        actualAmounts = new uint256[](2);
        actualAmounts[0] = tokenAAmount;
        actualAmounts[1] = tokenBAmount;

        emit WithdrawLiquidity(
            [tokenAAmount, tokenBAmount],
            [
                address(IPool(maverickExtraParams.poolAddress).tokenA()),
                address(IPool(maverickExtraParams.poolAddress).tokenB())
            ],
            [binslpAmountSummary, binslpBalanceSummary, binsLpTotalSupplySummary],
            maverickExtraParams.poolAddress,
            maverickExtraParams.tokenId,
            deployedBinIds
        );
        //slither-disable-end reentrancy-events
    }

    ///@dev Adoiding stack-too-deep-errors
    function _runWithdrawal(
        IRouter router,
        uint256[] calldata amounts,
        MaverickWithdrawalExtraParams memory maverickExtraParams
    ) private returns (uint256 tokenAAmount, uint256 tokenBAmount, IPool.BinDelta[] memory binDeltas) {
        (tokenAAmount, tokenBAmount, binDeltas) = router.removeLiquidity(
            IPool(maverickExtraParams.poolAddress),
            address(this),
            maverickExtraParams.tokenId,
            maverickExtraParams.maverickParams,
            amounts[0],
            amounts[1],
            maverickExtraParams.deadline
        );
    }

    function _collectBinSummary(
        IPool.BinDelta[] memory binDeltas,
        IPool pool,
        uint256 tokenId
    )
        private
        view
        returns (
            uint256 binslpAmountSummary,
            uint256 binslpBalanceSummary,
            uint256 binsLpTotalSupplySummary,
            uint256[] memory affectedBinIds
        )
    {
        affectedBinIds = new uint256[](binDeltas.length);
        for (uint256 i = 0; i < binDeltas.length; ++i) {
            IPool.BinDelta memory bin = binDeltas[i];
            affectedBinIds[i] = bin.binId;
            binslpAmountSummary += bin.deltaLpBalance;
            binslpBalanceSummary += pool.balanceOf(tokenId, bin.binId);
            binsLpTotalSupplySummary += pool.getBin(bin.binId).totalSupply;
        }
    }
}
//slither-disable-end similar-names
