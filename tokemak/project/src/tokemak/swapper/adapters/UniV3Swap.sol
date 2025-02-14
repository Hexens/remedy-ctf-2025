// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Path } from "src/tokemak/external/univ3/Path.sol";

import { IUniswapV3SwapRouter } from "src/tokemak/interfaces/external/uniswap/IUniswapV3SwapRouter.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";
import { BaseAdapter, ISyncSwapper } from "src/tokemak/swapper/adapters/BaseAdapter.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";

/**
 * @title UniV3Swap
 * @dev An adapter for Uniswap V3 that enables swapper functionality. Rather than swapping on a single pool,
 * this contract uses Uniswap's router to execute a swap across potentially multiple pools.
 *
 * swapData.pool: In the context of UniV3Swap, the pool attribute of SwapData is utilized to store the UniV3 router
 * address.
 *
 * swapData.data: Swap paths in Uniswap V3 are encoded in bytes format, denoted as `path` here.
 * Each path constitutes a sequence of token addresses and pool fees that represent the pools to be used in the swaps.
 * The path is encoded in the format:
 * (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut).
 * The `path` essentially defines the route taken by the swap operation.
 *
 */
contract UniV3Swap is BaseAdapter {
    using Path for bytes;

    constructor(
        address _router
    ) BaseAdapter(_router) { }

    /// @inheritdoc ISyncSwapper
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external pure override {
        bytes memory path = swapData.data;

        // retrieve the first and last token in the path
        (address sellAddress, address buyAddress) = _decodePath(path);

        // verify that the fromAddress and toAddress are in the path provided
        if (fromAddress != sellAddress) revert DataMismatch("fromAddress");
        if (swapData.token != buyAddress) revert DataMismatch("toAddress");
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

        IUniswapV3SwapRouter.ExactInputParams memory params = IUniswapV3SwapRouter.ExactInputParams({
            path: data,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: sellAmount,
            amountOutMinimum: minBuyAmount
        });

        return IUniswapV3SwapRouter(routerAddress).exactInput(params);
    }

    /**
     * @dev Decodes the encoded `path` byte sequence (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut)
     * to identify the first (sell) and the last (buy) token addresses involved in the multi-pool swap route.
     * @param path Encoded information specifying the swap path.
     * @return sellAddress The address of the token being sold (first tokenIn).
     * @return buyAddress The address of the token being purchased (last tokenOut).
     */
    function _decodePath(
        bytes memory path
    ) private pure returns (address sellAddress, address buyAddress) {
        bool hasMultiplePools = path.hasMultiplePools();
        // slither-disable-next-line unused-return
        (sellAddress, buyAddress,) = path.decodeFirstPool();

        while (hasMultiplePools) {
            path = path.skipToken();
            hasMultiplePools = path.hasMultiplePools();

            // We can only determine the last token in the path when there are no more pools left
            if (!hasMultiplePools) {
                // slither-disable-next-line unused-return
                (, address tokenOut,) = path.decodeFirstPool();
                buyAddress = tokenOut;
            }
        }

        return (sellAddress, buyAddress);
    }
}
