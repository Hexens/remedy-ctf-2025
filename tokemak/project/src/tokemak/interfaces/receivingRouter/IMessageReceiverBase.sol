// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IMessageReceiverBase {
    /// @notice Called by ReceivingRouter.sol on message from ccipRouter that targets inheriting contract
    /// @dev Any revert in this path will result in a ccip manual execution. Manual execution is only desireable in a
    /// revert path if we can change the underlying state to make a transaction pass on a manual execution. Otherwise,
    /// a failure event and return should be used.  See ReceivingRouter._ccipReceive for an example
    /// @param messageType Key for type of message being received
    /// @param messageNonce Nonce of message sent from source chain
    /// @param message Encoded message from origin contract and chain
    function onMessageReceive(bytes32 messageType, uint256 messageNonce, bytes memory message) external;
}
