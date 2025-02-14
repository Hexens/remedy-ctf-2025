// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { IRouter } from "src/tokemak/interfaces/external/aerodrome/IRouter.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";

import { BaseAdapter, ISyncSwapper } from "src/tokemak/swapper/adapters/BaseAdapter.sol";

contract AerodromeSwap is BaseAdapter {
    IRouter public immutable aerodromeRouter;

    constructor(address _aerodromeRouter, address _router) BaseAdapter(_router) {
        Errors.verifyNotZero(_aerodromeRouter, "aerodromeRouter");
        aerodromeRouter = IRouter(_aerodromeRouter);
    }

    /// @inheritdoc ISyncSwapper
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external view override {
        IRouter.Route[] memory routes = abi.decode(swapData.data, (IRouter.Route[]));

        uint256 routesLength = routes.length;
        if (routesLength == 0) revert Errors.ItemNotFound();
        if (fromAddress != routes[0].from) revert DataMismatch("fromToken");
        if (swapData.token != routes[routesLength - 1].to) revert DataMismatch("toToken");

        uint256 iter = 0;
        for (; iter < routesLength - 1;) {
            if (routes[iter].to != routes[iter + 1].from) revert DataMismatch("internalRoute");
            unchecked {
                ++iter;
            }
        }

        if (address(aerodromeRouter) != swapData.pool) revert DataMismatch("router");
    }

    /// @inheritdoc ISyncSwapper
    function swap(
        address routerAddress,
        address sellTokenAddress,
        uint256 sellAmount,
        address,
        uint256 minBuyAmount,
        bytes memory data
    ) external override onlyRouter returns (uint256) {
        LibAdapter._approve(IERC20(sellTokenAddress), routerAddress, sellAmount);

        uint256[] memory amounts = IRouter(routerAddress).swapExactTokensForTokens(
            sellAmount, minBuyAmount, abi.decode(data, (IRouter.Route[])), address(this), block.timestamp
        );

        uint256 amountReceived = amounts[amounts.length - 1];

        // slither-disable-next-line timestamp
        if (amountReceived < minBuyAmount) revert Errors.SlippageExceeded(minBuyAmount, amountReceived);

        return amounts[amounts.length - 1];
    }
}
