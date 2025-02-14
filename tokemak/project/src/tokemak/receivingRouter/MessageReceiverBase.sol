// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IMessageReceiverBase } from "src/tokemak/interfaces/receivingRouter/IMessageReceiverBase.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

/// @title Inherited by message receiver contracts for cross chain interactions.
abstract contract MessageReceiverBase is IMessageReceiverBase {
    /// @notice Ensure that receiving router registered on registry is only contract to call
    modifier onlyReceivingRouter() {
        ISystemRegistry systemRegistry = ISystemRegistry(ISystemComponent(address(this)).getSystemRegistry());
        if (msg.sender != address(systemRegistry.receivingRouter())) revert Errors.AccessDenied();
        _;
    }

    /// @inheritdoc IMessageReceiverBase
    function onMessageReceive(
        bytes32 messageType,
        uint256 messageNonce,
        bytes memory message
    ) external override onlyReceivingRouter {
        _onMessageReceive(messageType, messageNonce, message);
    }

    /// @dev This function will decode the incoming message and perform any other actions needed.
    /// @param message Bytes message to decode.
    // slither-disable-next-line unimplemented-functions
    function _onMessageReceive(bytes32 messageType, uint256 messageNonce, bytes memory message) internal virtual;
}
