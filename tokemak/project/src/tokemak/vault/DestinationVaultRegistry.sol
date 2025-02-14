//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IDestinationVaultFactory } from "src/tokemak/interfaces/vault/IDestinationVaultFactory.sol";
import { IDestinationVaultRegistry } from "src/tokemak/interfaces/vault/IDestinationVaultRegistry.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract DestinationVaultRegistry is SystemComponent, IDestinationVaultRegistry, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    IDestinationVaultFactory public factory;
    EnumerableSet.AddressSet private vaults;

    modifier onlyFactory() {
        if (msg.sender != address(factory)) {
            revert OnlyFactory();
        }
        _;
    }

    event FactorySet(address newFactory);
    event DestinationVaultRegistered(address vaultAddress, address caller);

    error OnlyFactory();
    error AlreadyRegistered(address vaultAddress);

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc IDestinationVaultRegistry
    function isRegistered(
        address destinationVault
    ) external view returns (bool) {
        return vaults.contains(destinationVault);
    }

    /// @inheritdoc IDestinationVaultRegistry
    function verifyIsRegistered(
        address destinationVault
    ) external view override {
        if (!vaults.contains(destinationVault)) revert Errors.NotRegistered();
    }

    /// @inheritdoc IDestinationVaultRegistry
    function register(
        address newDestinationVault
    ) external onlyFactory {
        Errors.verifyNotZero(newDestinationVault, "newDestinationVault");

        if (!vaults.add(newDestinationVault)) {
            revert AlreadyRegistered(newDestinationVault);
        }

        emit DestinationVaultRegistered(newDestinationVault, msg.sender);
    }

    /// @inheritdoc IDestinationVaultRegistry
    function listVaults() external view returns (address[] memory) {
        return vaults.values();
    }

    /// @notice Changes the factory that is allowed to register new vaults
    /// @dev Systems must match
    /// @param newAddress Address of the new factory
    function setVaultFactory(
        address newAddress
    ) external hasRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER) {
        Errors.verifyNotZero(newAddress, "newAddress");
        Errors.verifySystemsMatch(address(this), newAddress);

        emit FactorySet(newAddress);
        factory = IDestinationVaultFactory(newAddress);
    }
}
