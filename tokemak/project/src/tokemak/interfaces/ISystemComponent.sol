// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/// @notice Stores a reference to the registry for this system
interface ISystemComponent {
    /// @notice The system instance this contract is tied to
    function getSystemRegistry() external view returns (address registry);
}
