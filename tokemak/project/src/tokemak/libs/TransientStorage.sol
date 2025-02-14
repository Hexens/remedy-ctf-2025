// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

library TransientStorage {
    /// @notice Stores bytes data in transient storage
    /// @dev Uses assembly to efficiently store data in transient storage slots
    /// @param data The bytes data to be stored
    /// @param slot The starting slot in transient storage to store the data
    function setBytes(bytes memory data, uint256 slot) public {
        // Store the data
        //solhint-disable-next-line no-inline-assembly
        assembly {
            let dataLength := mload(data)
            tstore(slot, dataLength)
            for { let i := 0 } lt(i, dataLength) { i := add(i, 32) } {
                tstore(add(slot, add(1, div(i, 32))), mload(add(data, add(32, i))))
            }
        }
    }

    /// @notice Retrieves bytes data from transient storage
    /// @dev Uses assembly to efficiently retrieve data from transient storage slots
    /// @param slot The starting slot in transient storage to retrieve the data
    /// @return newData The bytes data retrieved from transient storage
    function getBytes(
        uint256 slot
    ) public view returns (bytes memory newData) {
        // Retrieve the data
        //solhint-disable-next-line no-inline-assembly
        assembly {
            let dataLength := tload(slot)
            newData := mload(0x40)
            mstore(newData, dataLength)
            for { let i := 0 } lt(i, dataLength) { i := add(i, 32) } {
                mstore(add(newData, add(32, i)), tload(add(slot, add(1, div(i, 32)))))
            }
            mstore(0x40, add(newData, add(32, dataLength)))
        }
    }

    /// @notice Clears bytes data from transient storage
    /// @dev Uses assembly to efficiently clear data from transient storage slots
    /// @param slot The starting slot in transient storage to clear the data
    function clearBytes(
        uint256 slot
    ) public {
        // Clear the data
        //solhint-disable-next-line no-inline-assembly
        assembly {
            let dataLength := tload(slot)
            tstore(slot, 0)
            for { let i := 0 } lt(i, dataLength) { i := add(i, 32) } { tstore(add(slot, add(1, div(i, 32))), 0) }
        }
    }

    /// @notice Checks if data exists in transient storage
    /// @dev Uses assembly to efficiently check if data exists in transient storage slots
    /// @param slot The starting slot in transient storage to check for data
    /// @return exists True if data exists, false otherwise
    function dataExists(
        uint256 slot
    ) public view returns (bool) {
        // Check if data exists
        //solhint-disable-next-line no-inline-assembly
        assembly {
            let dataLength := tload(slot)
            mstore(0x0, gt(dataLength, 0))
            return(0x0, 32)
        }
    }
}
