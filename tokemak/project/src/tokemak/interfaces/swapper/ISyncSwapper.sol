// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";

interface ISyncSwapper {
    error DataMismatch(string element);
    error InvalidIndex();

    /**
     * @notice Returns address of swap router that can access SyncSwapper contract
     */
    function router() external view returns (ISwapRouter);

    /**
     * @notice Swaps sellToken for buyToken
     * @param pool The address of the pool for the swapper
     * @param sellTokenAddress The address of the token to sell
     * @param sellAmount The amount of sellToken to sell
     * @param buyTokenAddress The address of the token to buy
     * @param minBuyAmount The minimum amount of buyToken expected
     * @param data Additional data used differently by the different swappers
     * @return actualBuyAmount The actual amount received from the swap
     */
    function swap(
        address pool,
        address sellTokenAddress,
        uint256 sellAmount,
        address buyTokenAddress,
        uint256 minBuyAmount,
        bytes memory data
    ) external returns (uint256 actualBuyAmount);

    /**
     * @notice Validates that the swapData contains the correct information, ensuring that the encoded data contains the
     * correct 'fromAddress' and 'toAddress' (swapData.token), and verifies that these tokens are in the pool
     * @dev This function should revert with a DataMismatch error if the swapData is invalid
     * @param fromAddress The address from which the swap originates
     * @param swapData The data associated with the swap that needs to be validated
     */
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external view;
}
