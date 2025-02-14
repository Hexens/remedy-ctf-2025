// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IDestinationVaultExtension {
    /// @notice Execute a destination vault extension
    /// @param data Data to be decoded in function call
    function execute(
        bytes calldata data
    ) external;
}
