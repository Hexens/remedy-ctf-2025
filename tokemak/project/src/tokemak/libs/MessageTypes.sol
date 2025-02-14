// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

library MessageTypes {
    /// @notice LST Base APR snapshots
    bytes32 public constant LST_SNAPSHOT_MESSAGE_TYPE = keccak256("LST_SNAPSHOT");

    /// @notice Used to transfer LST snapshot data to other chain.
    struct LSTDestinationInfo {
        uint256 snapshotTimestamp;
        uint256 newBaseApr;
        uint256 currentEthPerToken;
    }

    /// @notice LST Eth Per Token changes
    bytes32 public constant LST_BACKING_MESSAGE_TYPE = keccak256("LST_BACKING");

    /// @notice Message structure for `LST_BACKING_MESSAGE_TYPE`
    struct LstBackingMessage {
        address token;
        uint208 ethPerToken;
        uint48 timestamp;
    }
}
