// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/// @notice An oracle that can provide prices for single or multiple classes of tokens
interface IPriceOracle {
    /// @notice Returns a fair price for the provided token in ETH
    /// @dev May require additional registration with the provider before being used for a token
    /// @param token Token to get the price of
    /// @return price The price of the token in ETH
    function getPriceInEth(
        address token
    ) external returns (uint256 price);

    /// @notice Retrieve the description of the oracle
    /// @return description
    function getDescription() external view returns (string memory);
}
