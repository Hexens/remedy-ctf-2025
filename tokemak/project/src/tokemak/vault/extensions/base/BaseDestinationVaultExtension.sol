// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IDestinationVaultExtension } from "src/tokemak/interfaces/vault/IDestinationVaultExtension.sol";
import { SystemComponent, ISystemRegistry } from "src/tokemak/SystemComponent.sol";

/// @title A base contract for all destination vault extensions
/// @dev This contract must be used in a delegatecall context
abstract contract BaseDestinationVaultExtension is SystemComponent, IDestinationVaultExtension {
    /// @dev address(this) will be the DVs address in a delegatecall context
    modifier onlyDestinationVault() {
        systemRegistry.destinationVaultRegistry().verifyIsRegistered(address(this));
        _;
    }

    // slither-disable-next-line similar-names
    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) { }
}
