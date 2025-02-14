// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/// @title Keep track of Vaults created through the Vault Factory
interface IAutopoolRegistry {
    ///////////////////////////////////////////////////////////////////
    //                        Errors
    ///////////////////////////////////////////////////////////////////

    error VaultNotFound(address vaultAddress);
    error VaultAlreadyExists(address vaultAddress);

    ///////////////////////////////////////////////////////////////////
    //                        Events
    ///////////////////////////////////////////////////////////////////
    event VaultAdded(address indexed asset, address indexed vault);
    event VaultRemoved(address indexed asset, address indexed vault);

    ///////////////////////////////////////////////////////////////////
    //                        Functions
    ///////////////////////////////////////////////////////////////////

    /// @notice Checks if an address is a valid vault
    /// @param vaultAddress Vault address to be added
    function isVault(
        address vaultAddress
    ) external view returns (bool);

    /// @notice Registers a vault
    /// @param vaultAddress Vault address to be added
    function addVault(
        address vaultAddress
    ) external;

    /// @notice Removes vault registration
    /// @param vaultAddress Vault address to be removed
    function removeVault(
        address vaultAddress
    ) external;

    /// @notice Returns a list of all registered vaults
    function listVaults() external view returns (address[] memory);

    /// @notice Returns a list of all registered vaults for a given asset
    /// @param asset Asset address
    function listVaultsForAsset(
        address asset
    ) external view returns (address[] memory);

    /// @notice Returns a list of all registered vaults for a given type
    /// @param _vaultType Vault type
    function listVaultsForType(
        bytes32 _vaultType
    ) external view returns (address[] memory);
}
