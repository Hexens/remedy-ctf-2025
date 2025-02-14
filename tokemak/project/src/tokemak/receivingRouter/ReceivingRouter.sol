// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

import { IMessageReceiverBase } from "src/tokemak/interfaces/receivingRouter/IMessageReceiverBase.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { CrossChainMessagingUtilities as CCUtils, IRouterClient } from "src/tokemak/libs/CrossChainMessagingUtilities.sol";
import { Client } from "src/tokemak/external/chainlink/ccip/Client.sol";

import { CCIPReceiver } from "src/tokemak/external/chainlink/ccip/CCIPReceiver.sol";

/// @title Receives and routes messages from another chain using Chainlink CCIP
contract ReceivingRouter is CCIPReceiver, SystemComponent, SecurityBase {
    /// =====================================================
    /// Public vars
    /// =====================================================

    /// @notice keccak256(address origin, uint256 sourceChainSelector, bytes32 messageType) => address[]
    mapping(bytes32 => address[]) public messageReceivers;

    /// @notice uint64 sourceChainSelector => address[] senders, contract that sends message across chain
    /// @dev Multiple to handle replacing MessageProxy on source chain.
    mapping(uint64 => address[2]) public sourceChainSenders;

    /// =====================================================
    /// Errors
    /// =====================================================

    /// @notice Thrown when a message receiver does not exist in storage.
    error MessageReceiverDoesNotExist(address notReceiver);

    /// @notice Thrown when an invalid address sends a message from the source chain
    error InvalidSenderFromSource(
        uint256 sourceChainSelector,
        address sourceChainSender,
        address sourceChainSenderRegistered1,
        address sourceChainSenderRegistered2
    );

    /// @notice Thrown when no message receivers are registered
    error NoMessageReceiversRegistered(address messageOrigin, bytes32 messageType, uint64 sourceChainSelector);

    /// =====================================================
    /// Events
    /// =====================================================

    /// @notice Emitted when message is built to be sent for message origin, type, and source chain.
    event MessageData(
        uint256 messageNonce,
        address messageOrigin,
        bytes32 messageType,
        bytes32 ccipMessageId,
        uint64 sourceChainSelector,
        bytes message
    );

    /// @notice Emitted when the contract that sends messages from the source chain is registered.
    event SourceChainSenderSet(uint64 sourceChainSelector, address sourceChainSender);

    /// @notice Emitted when source contract is deleted.
    event SourceChainSenderDeleted(uint64 sourceChainSelector);

    /// @notice Emitted when a message is successfully sent to a message receiver contract.
    event MessageReceived(address messageReceiver, bytes message);

    /// @notice Emitted when a message receiver is added
    event MessageReceiverAdded(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToAdd
    );

    /// @notice Emitted when a message receiver is deleted
    event MessageReceiverDeleted(
        address messageOrigin, uint64 sourceChainSelector, bytes32 messageType, address messageReceiverToRemove
    );

    /// =====================================================
    /// Failure Events
    /// =====================================================

    /// @notice Emitted when message versions don't match
    event MessageVersionMismatch(uint256 versionSource, uint256 versionReceiver);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        address _ccipRouter,
        ISystemRegistry _systemRegistry
    )
        CCIPReceiver(_ccipRouter)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @inheritdoc CCIPReceiver
    /// @dev This function can fail if incorrect data comes in on the Any2EVMMessage.data field. Special care
    ///   should be taken care to make sure versions always match
    function _ccipReceive(
        Client.Any2EVMMessage memory ccipMessage
    ) internal override {
        uint64 sourceChainSelector = ccipMessage.sourceChainSelector;
        bytes memory messageData = ccipMessage.data;

        // Scope stack too deep
        {
            // Checking that sender in Any2EVMMessage struct is the same as the one we have registered for source
            address proxySender = abi.decode(ccipMessage.sender, (address));
            // slither-disable-start similar-names
            address registeredSender1 = sourceChainSenders[sourceChainSelector][0];
            address registeredSender2 = sourceChainSenders[sourceChainSelector][1];
            // slither-disable-end similar-names
            if (proxySender != registeredSender1 && proxySender != registeredSender2) {
                revert InvalidSenderFromSource(sourceChainSelector, proxySender, registeredSender1, registeredSender2);
            }
        }

        CCUtils.Message memory messageFromProxy = decodeMessage(messageData);

        // Scoping for stack too deep
        {
            // Checking Message struct versioning
            uint256 sourceVersion = messageFromProxy.version;
            uint256 receiverVersion = CCUtils.getVersion();
            if (sourceVersion != receiverVersion) {
                emit MessageVersionMismatch(sourceVersion, receiverVersion);
                return;
            }
        }

        address origin = messageFromProxy.messageOrigin;
        bytes32 messageType = messageFromProxy.messageType;
        uint256 messageNonce = messageFromProxy.messageNonce;
        bytes memory message = messageFromProxy.message;

        bytes32 senderKey = _getMessageReceiversKey(origin, sourceChainSelector, messageType);
        address[] memory messageReceiversForRoute = messageReceivers[senderKey];
        uint256 messageReceiversForRouteLength = messageReceiversForRoute.length;

        // Receivers registration act as security, this accounts for zero checks for type, origin, selector.
        if (messageReceiversForRouteLength == 0) {
            revert NoMessageReceiversRegistered(origin, messageType, sourceChainSelector);
        }

        emit MessageData(messageNonce, origin, messageType, ccipMessage.messageId, sourceChainSelector, message);

        // slither-disable-start reentrancy-events
        // Loop through stored receivers, send messages off to them
        for (uint256 i = 0; i < messageReceiversForRouteLength; ++i) {
            address currentMessageReceiver = messageReceiversForRoute[i];

            // Any failures will bubble and result in the option for a manual execution of this transaction
            // via ccip UI.
            emit MessageReceived(currentMessageReceiver, message);
            IMessageReceiverBase(currentMessageReceiver).onMessageReceive(messageType, messageNonce, message);
        }
        // slither-disable-end reentrancy-events
    }

    /// @notice Sets message receivers for an origin, type, source selector combination
    /// @param messageOrigin Original sender of message on source chain.
    /// @param messageType Bytes32 message type
    /// @param sourceChainSelector Selector of the source chain
    /// @param messageReceiversToSet Array of receiver addresses to set
    function setMessageReceivers(
        address messageOrigin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory messageReceiversToSet
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        // Verify no zeros
        Errors.verifyNotZero(messageOrigin, "messageOrigin");
        Errors.verifyNotZero(messageType, "messageType");

        // Store and verify length of array
        uint256 messageReceiversToSetLength = messageReceiversToSet.length;
        Errors.verifyNotZero(messageReceiversToSetLength, "messageReceiversToSetLength");

        // Check to make sure that chain selector is valid and has at least one sender set
        if (
            sourceChainSenders[sourceChainSelector][0] == address(0)
                && sourceChainSenders[sourceChainSelector][1] == address(0)
        ) {
            revert CCUtils.ChainNotSupported(sourceChainSelector);
        }

        bytes32 receiverKey = _getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType);

        // Loop and add to storage array
        for (uint256 i = 0; i < messageReceiversToSetLength; ++i) {
            address receiverToAdd = messageReceiversToSet[i];
            Errors.verifyNotZero(receiverToAdd, "receiverToAdd");

            address[] memory currentStoredMessageReceivers = messageReceivers[receiverKey];
            uint256 currentStoredMessageReceiversLength = currentStoredMessageReceivers.length;

            // Check for duplicates being added
            if (currentStoredMessageReceiversLength > 0) {
                for (uint256 j = 0; j < currentStoredMessageReceiversLength; ++j) {
                    if (receiverToAdd == currentStoredMessageReceivers[j]) {
                        revert Errors.ItemExists();
                    }
                }
            }

            emit MessageReceiverAdded(messageOrigin, sourceChainSelector, messageType, receiverToAdd);
            messageReceivers[receiverKey].push(receiverToAdd);
        }
    }

    /// @notice Removes registered message receivers
    /// @param messageOrigin Origin of message
    /// @param messageType Type of message
    /// @param sourceChainSelector Selector of the source chain
    /// @param messageReceiversToRemove Array of sender addresses to remove
    function removeMessageReceivers(
        address messageOrigin,
        bytes32 messageType,
        uint64 sourceChainSelector,
        address[] memory messageReceiversToRemove
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        // Check array length
        uint256 messageReceiversToRemoveLength = messageReceiversToRemove.length;
        Errors.verifyNotZero(messageReceiversToRemoveLength, "messageReceiversToRemoveLength");

        // Get stored receivers as storage, manipulating later.
        // Acts as security for origin, type, selector.  If none registered, will revert.  Zeros checked on reg
        address[] storage messageReceiversStored =
            messageReceivers[_getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType)];

        // Loop through removal array
        for (uint256 i = 0; i < messageReceiversToRemoveLength; ++i) {
            // Check for storage length.  Do this in loop because we are updating as we go
            uint256 receiversStoredLength = messageReceiversStored.length;
            if (receiversStoredLength == 0) {
                revert Errors.ItemNotFound();
            }

            address receiverToRemove = messageReceiversToRemove[i];
            Errors.verifyNotZero(receiverToRemove, "receiverToRemove");

            // For each route we want to remove, loop through stored routes to make sure it exists
            uint256 j = 0;
            for (; j < receiversStoredLength; ++j) {
                // If route to add is equal to a stored route, remove.
                if (receiverToRemove == messageReceiversStored[j]) {
                    emit MessageReceiverDeleted(messageOrigin, sourceChainSelector, messageType, receiverToRemove);

                    // For each removal, overwrite index to remove and pop last element
                    messageReceiversStored[j] = messageReceiversStored[receiversStoredLength - 1];
                    messageReceiversStored.pop();

                    // Can only have one message route per dest chain selector, when we find it break for loop.
                    break;
                }
            }

            // If we get to the end of the messageReceiversStored array, item to be deleted does not exist.
            if (j == receiversStoredLength) {
                revert Errors.ItemNotFound();
            }
        }
    }

    /// @notice Sets valid sender for source chain
    /// @dev This will be the message proxy contract on the source chain
    /// @dev Used to add and remove source chain senders
    /// @param sourceChainSelector Selector for source chain
    /// @param sourceChainSender Sender from the source chain, MessageProxy contract
    /// @param idx Index of chain sender to set
    function setSourceChainSenders(
        uint64 sourceChainSelector,
        address sourceChainSender,
        uint256 idx
    ) external hasRole(Roles.RECEIVING_ROUTER_MANAGER) {
        if (idx != 0 && idx != 1) {
            revert Errors.InvalidParam("idx");
        }

        if (sourceChainSender != address(0)) {
            // Check that source chain selector registered with Chainlink router.  Will differ by chain
            CCUtils.validateChain(IRouterClient(i_ccipRouter), sourceChainSelector);

            // Check if sourceChainSender already exists
            if (
                sourceChainSenders[sourceChainSelector][0] == sourceChainSender
                    || sourceChainSenders[sourceChainSelector][1] == sourceChainSender
            ) {
                revert Errors.ItemExists();
            }
        }

        emit SourceChainSenderSet(sourceChainSelector, sourceChainSender);
        sourceChainSenders[sourceChainSelector][idx] = sourceChainSender;
    }

    /// =====================================================
    /// Functions - Getters
    /// =====================================================

    /// @notice Gets all message receivers for origin, source chain, message type
    /// @return receivers address array of the message receivers
    function getMessageReceivers(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) external view returns (address[] memory receivers) {
        bytes32 receiversKey = _getMessageReceiversKey(messageOrigin, sourceChainSelector, messageType);
        receivers = messageReceivers[receiversKey];
    }

    /// @notice Returns array of source chain senders
    /// @param sourceChainSelector Selector of the source chain for a sender
    function getSourceChainSenders(
        uint64 sourceChainSelector
    ) external view returns (address[] memory senders) {
        senders = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            senders[i] = sourceChainSenders[sourceChainSelector][i];
        }
    }

    /// =====================================================
    /// Functions - Helpers
    /// =====================================================

    /// @dev Decodes CCUtils.Message struct sent from source chain
    function decodeMessage(
        bytes memory encodedMessage
    ) private pure returns (CCUtils.Message memory) {
        return abi.decode(encodedMessage, (CCUtils.Message));
    }

    /// @dev Hashes together origin, sourceChainSelector, messageType to get key for destinations
    function _getMessageReceiversKey(
        address messageOrigin,
        uint64 sourceChainSelector,
        bytes32 messageType
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(messageOrigin, sourceChainSelector, messageType));
    }
}
