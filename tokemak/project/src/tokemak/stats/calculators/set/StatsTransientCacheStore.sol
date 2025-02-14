// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { TransientStorage } from "src/tokemak/libs/TransientStorage.sol";

/// @notice Cache store for transient calculator data
contract StatsTransientCacheStore is SecurityBase, SystemComponent {
    /// =====================================================
    /// Private Vars
    /// =====================================================

    /// @dev Stores keys that are currently set in transient storage
    uint256 private constant SET_KEYS = uint256(keccak256(bytes("SET_KEYS"))) - 1;

    /// =====================================================
    /// Errors
    /// =====================================================

    /// @notice Thrown when caller attempts to set a blocked key
    error InvalidKey(bytes32 key);

    /// @notice Thrown when caller attempts to overwrite data in use
    error DataExists();

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @notice Save current stat for the provided calculator ids
    /// @dev Does not check for duplicate sets
    /// @param aprIds Calculators to store data for
    /// @param data Data to return when current() is called for the specified calculators
    function writeTransient(
        bytes32[] memory aprIds,
        bytes[] memory data
    ) external hasRole(Roles.STATS_CACHE_SET_TRANSIENT_EXECUTOR) {
        uint256 len = data.length;
        Errors.verifyNotZero(len, "len");
        Errors.verifyArrayLengths(aprIds.length, len, "arr");

        // Not allowed to overwrite data in use
        bool hasData = TransientStorage.dataExists(SET_KEYS);
        if (hasData) {
            revert DataExists();
        }

        // Save the keys we're setting so we can clear them later
        TransientStorage.setBytes(abi.encode(aprIds), SET_KEYS);

        for (uint256 i = 0; i < len;) {
            // Do not allow setting of our tracking var
            if (uint256(aprIds[i]) == SET_KEYS || uint256(aprIds[0]) == 0) {
                revert InvalidKey(aprIds[i]);
            }

            // Setting empty data allowed, hasTransient() will return false
            TransientStorage.setBytes(data[i], uint256(aprIds[i]));

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Clear any data that has been set via writeTransient()
    function clearTransient() external hasRole(Roles.STATS_CACHE_SET_TRANSIENT_EXECUTOR) {
        bytes memory keys = TransientStorage.getBytes(SET_KEYS);
        TransientStorage.clearBytes(SET_KEYS);

        bytes32[] memory aprIds = abi.decode(keys, (bytes32[]));
        uint256 len = aprIds.length;
        for (uint256 i = 0; i < len;) {
            TransientStorage.clearBytes(uint256(aprIds[i]));

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns whether we currently have transient data stored for the calculator
    function hasTransient(
        bytes32 aprId
    ) external view returns (bool) {
        return TransientStorage.dataExists(uint256(aprId));
    }

    /// @notice Returns data currently stored for the calculator in transient storage
    function getTransient(
        bytes32 aprId
    ) external view returns (bytes memory) {
        return TransientStorage.getBytes(uint256(aprId));
    }
}
