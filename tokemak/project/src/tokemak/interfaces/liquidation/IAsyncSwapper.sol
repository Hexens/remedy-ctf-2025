// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

struct SwapParams {
    /// @dev The address of the token to be sold.
    address sellTokenAddress;
    /// @dev The amount of tokens to be sold.
    uint256 sellAmount;
    /// @dev The address of the token to be bought.
    address buyTokenAddress;
    /// @dev The expected minimum amount of tokens to be bought.
    uint256 buyAmount;
    /// @dev Data payload to be used for complex swap operations.
    bytes data;
    /// @dev Extra data payload reserved for future development. This field allows for additional information
    /// or functionality to be added without changing the struct and interface.
    bytes extraData;
    /// @dev Execution deadline in timestamp format
    uint256 deadline;
}

interface IAsyncSwapper {
    error TokenAddressZero();
    error SwapFailed();
    error InsufficientBuyAmountReceived(uint256 buyTokenAmountReceived, uint256 buyAmount);
    error InsufficientSellAmount();
    error InsufficientBuyAmount();
    error InsufficientBalance(uint256 balanceNeeded, uint256 balanceAvailable);

    event Swapped(
        address indexed sellTokenAddress,
        address indexed buyTokenAddress,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 buyTokenAmountReceived
    );

    /**
     * @notice Swaps sellToken for buyToken
     * @param swapParams Encoded swap data
     * @return buyTokenAmountReceived The amount of buyToken received from the swap
     */
    function swap(
        SwapParams memory swapParams
    ) external returns (uint256 buyTokenAmountReceived);
}
