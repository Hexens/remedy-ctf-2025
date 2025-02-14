// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IDestinationAdapter } from "src/tokemak/interfaces/destinations/IDestinationAdapter.sol";
import { IDestinationRegistry } from "src/tokemak/interfaces/destinations/IDestinationRegistry.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract DestinationRegistry is SystemComponent, SecurityBase, IDestinationRegistry {
    mapping(bytes32 => IDestinationAdapter) public destinations;
    mapping(bytes32 => bool) public allowedTypes;

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc IDestinationRegistry
    function register(
        bytes32[] calldata destinationTypes,
        address[] calldata targets
    ) public override hasRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER) {
        Errors.verifyArrayLengths(destinationTypes.length, targets.length, "types+targets");
        for (uint256 i = 0; i < destinationTypes.length; ++i) {
            bytes32 destination = destinationTypes[i];
            if (!isWhitelistedDestination(destination)) {
                revert NotAllowedDestination();
            }
            address target = targets[i];
            Errors.verifyNotZero(target, "target");

            if (address(destinations[destination]) != address(0)) {
                revert DestinationAlreadySet();
            }

            Errors.verifySystemsMatch(address(this), target);

            destinations[destination] = IDestinationAdapter(target);
        }
        emit Register(destinationTypes, targets);
    }

    /// @inheritdoc IDestinationRegistry
    function replace(
        bytes32[] calldata destinationTypes,
        address[] calldata targets
    ) public override hasRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER) {
        Errors.verifyArrayLengths(destinationTypes.length, targets.length, "types+targets");
        for (uint256 i = 0; i < destinationTypes.length; ++i) {
            address target = targets[i];
            Errors.verifyNotZero(target, "target");

            Errors.verifySystemsMatch(address(this), target);

            bytes32 destination = destinationTypes[i];
            IDestinationAdapter existingDestination = destinations[destination];
            Errors.verifyNotZero(address(existingDestination), "existingDestination");

            if (address(existingDestination) == target) {
                revert DestinationAlreadySet();
            }
            destinations[destination] = IDestinationAdapter(target);
        }
        emit Replace(destinationTypes, targets);
    }

    /// @inheritdoc IDestinationRegistry
    function unregister(
        bytes32[] calldata destinationTypes
    ) public override hasRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER) {
        for (uint256 i = 0; i < destinationTypes.length; ++i) {
            bytes32 destination = destinationTypes[i];
            Errors.verifyNotZero(address(destinations[destination]), "destAddress");
            //slither-disable-next-line costly-loop
            delete destinations[destination];
        }
        emit Unregister(destinationTypes);
    }

    /// @inheritdoc IDestinationRegistry
    function getAdapter(
        bytes32 destinationType
    ) public view override returns (IDestinationAdapter target) {
        target = destinations[destinationType];
        Errors.verifyNotZero(address(target), "target");
    }

    /// @inheritdoc IDestinationRegistry
    function addToWhitelist(
        bytes32[] calldata destinationTypes
    ) external override hasRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER) {
        for (uint256 i = 0; i < destinationTypes.length; ++i) {
            if (allowedTypes[destinationTypes[i]]) {
                revert DestinationAlreadySet();
            }
            allowedTypes[destinationTypes[i]] = true;
        }
        emit Whitelist(destinationTypes);
    }

    /// @inheritdoc IDestinationRegistry
    function removeFromWhitelist(
        bytes32[] calldata destinationTypes
    ) external override hasRole(Roles.DESTINATION_VAULT_REGISTRY_MANAGER) {
        for (uint256 i = 0; i < destinationTypes.length; ++i) {
            bytes32 destination = destinationTypes[i];
            if (!allowedTypes[destination]) {
                revert Errors.ItemNotFound();
            }
            if (address(destinations[destination]) != address(0)) {
                // cannot remove from whitelist already registered type – must unregister first
                revert DestinationAlreadySet();
            }
            //slither-disable-next-line costly-loop
            delete allowedTypes[destination];
        }
        emit RemoveFromWhitelist(destinationTypes);
    }

    /// @inheritdoc IDestinationRegistry
    function isWhitelistedDestination(
        bytes32 destinationType
    ) public view override returns (bool) {
        return allowedTypes[destinationType];
    }
}
