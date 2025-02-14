// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";

interface ISwapRouterV2 is ISwapRouter {
    struct UserSwapData {
        address fromToken;
        address toToken;
        address target;
        bytes data;
    }

    function initTransientSwap(
        UserSwapData[] memory customRoutes
    ) external;

    function exitTransientSwap() external;
}
