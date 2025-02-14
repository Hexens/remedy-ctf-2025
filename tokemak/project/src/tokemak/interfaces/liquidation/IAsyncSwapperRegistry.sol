// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IAsyncSwapperRegistry {
    event SwapperAdded(address indexed item);
    event SwapperRemoved(address indexed item);

    /// @notice Registers an item
    /// @param item Item address to be added
    function register(
        address item
    ) external;

    /// @notice Removes item registration
    /// @param item Item address to be removed
    function unregister(
        address item
    ) external;

    /// @notice Returns a list of all registered items
    function list() external view returns (address[] memory);

    /// @notice Checks if an address is a valid item
    /// @param item Item address to be checked
    function isRegistered(
        address item
    ) external view returns (bool);

    /// @notice Checks if an address is a valid swapper and reverts if not
    /// @param item Swapper address to be checked
    function verifyIsRegistered(
        address item
    ) external view;
}
