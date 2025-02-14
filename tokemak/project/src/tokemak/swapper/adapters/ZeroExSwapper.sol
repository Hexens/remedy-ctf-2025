// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract ZeroExSwapper {
    using SafeERC20 for IERC20;

    struct ZeroExSwapData {
        address approvalTarget;
        address swapTarget;
        address tokenRecipient;
        address fromToken;
        address toToken;
        bytes swapCallData;
    }

    error SwapFailed();

    function swap(
        ZeroExSwapData memory zeroExSwapData
    ) external {
        address fromToken = zeroExSwapData.fromToken;
        address approvalTarget = zeroExSwapData.approvalTarget;
        LibAdapter._approve(IERC20(fromToken), approvalTarget, type(uint256).max);

        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = zeroExSwapData.swapTarget.call(zeroExSwapData.swapCallData);
        // slither-disable-end low-level-calls
        LibAdapter._approve(IERC20(fromToken), approvalTarget, 0);

        if (!success) {
            revert SwapFailed();
        }

        address toToken = zeroExSwapData.toToken;
        // return funds
        uint256 balance = IERC20(toToken).balanceOf(address(this));
        if (balance > 0) {
            IERC20(toToken).safeTransfer(zeroExSwapData.tokenRecipient, balance);
        }
    }
}
