// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/// @notice Interface for a deployed CustomSetOracle to access its functions and state variables
interface ICustomSetOracle {
    /// @notice Struct to hold the price, max age, and timestamp of a token in the prices mapping
    struct Price {
        uint192 price;
        uint32 maxAge;
        uint32 timestamp;
    }

    /// STATE VARIABLES

    /// @notice Maximum age a price can be from when it was originally queried
    function maxAge() external view returns (uint256);

    /// @notice All current prices for registered tokens
    function prices(
        address token
    ) external view returns (uint192 price, uint32 priceMaxAge, uint32 timestamp);

    /// FUNCTIONS

    /// @notice Register tokens that should be resolvable through this oracle
    /// @param tokens addresses of tokens to register
    /// @param maxAges the max allowed age of a tokens price before it will revert on retrieval
    function registerTokens(address[] memory tokens, uint256[] memory maxAges) external;

    /// @notice Update the price of one or more registered tokens
    /// @param tokens address of the tokens price we are setting
    /// @param ethPrices prices of the tokens we're setting
    /// @param queriedTimestamps the timestamps of when each price was queried
    function setPrices(
        address[] memory tokens,
        uint256[] memory ethPrices,
        uint256[] memory queriedTimestamps
    ) external;

    /// @notice Returns true for a token that is registered with this oracle
    /// @param token address to check
    function isRegistered(
        address token
    ) external view returns (bool);
}
