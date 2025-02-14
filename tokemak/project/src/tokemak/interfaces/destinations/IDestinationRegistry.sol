// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IDestinationAdapter } from "src/tokemak/interfaces/destinations/IDestinationAdapter.sol";

interface IDestinationRegistry {
    event Register(bytes32[] indexed destinationTypes, address[] indexed targets);
    event Replace(bytes32[] indexed destinationTypes, address[] indexed targets);
    event Unregister(bytes32[] indexed destinationTypes);

    event Whitelist(bytes32[] indexed destinationTypes);
    event RemoveFromWhitelist(bytes32[] indexed destinationTypes);

    error InvalidAddress(address addr);
    error NotAllowedDestination();
    error DestinationAlreadySet();

    /**
     * @notice Adds a new addresses of the given destination types
     * @dev Fails if trying to overwrite previous value of the same destination type
     * @param destinationTypes Ones from the destination type whitelist
     * @param targets addresses of the deployed DestinationAdapters, cannot be 0
     */
    function register(bytes32[] calldata destinationTypes, address[] calldata targets) external;

    /**
     * @notice Replaces an addresses of the given destination types
     * @dev Fails if given destination type was not set previously
     * @param destinationTypes Ones from the destination type whitelist
     * @param targets addresses of the deployed DestinationAdapters, cannot be 0
     */
    function replace(bytes32[] calldata destinationTypes, address[] calldata targets) external;

    /**
     * @notice Removes an addresses of the given pre-registered destination types
     * @param destinationTypes Ones from the destination types whitelist
     */
    function unregister(
        bytes32[] calldata destinationTypes
    ) external;

    /**
     * @notice Gives an address of the given destination type
     * @dev Should revert on missing destination
     * @param destination One from the destination type whitelist
     */
    function getAdapter(
        bytes32 destination
    ) external returns (IDestinationAdapter);

    /**
     * @notice Adds given destination types to the whitelist
     * @param destinationTypes Types to whitelist
     */
    function addToWhitelist(
        bytes32[] calldata destinationTypes
    ) external;

    /**
     * @notice Removes given pre-whitelisted destination types
     * @param destinationTypes Ones from the destination type whitelist
     */
    function removeFromWhitelist(
        bytes32[] calldata destinationTypes
    ) external;

    /**
     * @notice Checks if the given destination type is whitelisted
     * @param destinationType Type to verify
     */
    function isWhitelistedDestination(
        bytes32 destinationType
    ) external view returns (bool);
}
