// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { MessageTypes } from "src/tokemak/libs/MessageTypes.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { MessageReceiverBase } from "src/tokemak/receivingRouter/MessageReceiverBase.sol";

/// @notice Tracks bridge LST eth/token values
contract EthPerTokenStore is SystemComponent, SecurityBase, MessageReceiverBase {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Max age of a value before it starts to revert on read
    uint256 public maxAgeSeconds;

    /// @notice Stored nonce sent from source chain
    uint256 public lastStoredNonce;

    /// @notice Returns whether a token is registered with this contract
    mapping(address => bool) public registered;

    /// @notice Returns current data about the given token
    mapping(address => TokenTrack) public trackedTokens;

    /// =====================================================
    /// Events
    /// =====================================================

    event EthPerTokenUpdated(address indexed token, uint256 amount, uint256 timestamp);
    event MaxAgeSet(uint256 newValue);
    event TokenRegistered(address token);
    event TokenUnregistered(address token);

    /// =====================================================
    /// Failure Events
    /// =====================================================

    /// @notice Emitted when a stale nonce is sent from the source chain
    event StaleNonce(address token, uint256 lastStoredNonce, uint256 newSourceChainNonce);

    /// =====================================================
    /// Errors
    /// =====================================================

    error UnsupportedToken(address token);
    error ValueNotAvailable(address token);

    /// =====================================================
    /// Structs
    /// =====================================================

    struct TokenTrack {
        uint208 ethPerToken;
        uint48 lastSetTimestamp;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        maxAgeSeconds = 3 days;
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Set the max age in seconds before reads start to revert
    /// @param age New max age in seconds
    function setMaxAgeSeconds(
        uint256 age
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        Errors.verifyNotZero(age, "age");

        // Sanity check
        if (age > 10 days) {
            revert Errors.InvalidParam("age");
        }

        maxAgeSeconds = age;
        emit MaxAgeSet(age);
    }

    /// @notice Register the specified token to allow it to be tracked
    /// @param token Token to register
    function registerToken(
        address token
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        Errors.verifyNotZero(token, "token");

        if (registered[token]) {
            revert Errors.AlreadyRegistered(token);
        }
        registered[token] = true;
        emit TokenRegistered(token);
    }

    /// @notice Unregister the specified token
    /// @dev Will delete currently tracked data
    /// @param token Token to unregister
    function unregisterToken(
        address token
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        if (!registered[token]) {
            revert Errors.NotRegistered();
        }
        registered[token] = false;
        delete trackedTokens[token];
        emit TokenUnregistered(token);
    }

    /// @notice Returns the current value for the given token
    /// @dev Reverts if value stale or not registered. Same error for both conditions
    /// @param token Token to lookup value for
    function getEthPerToken(
        address token
    ) external view returns (uint256 ethPerToken, uint256 lastSetTimestamp) {
        TokenTrack memory data = trackedTokens[token];

        // If stale or not registered revert
        // slither-disable-next-line timestamp
        if (data.lastSetTimestamp < block.timestamp - maxAgeSeconds) {
            revert ValueNotAvailable(token);
        }
        return (data.ethPerToken, data.lastSetTimestamp);
    }

    /// =====================================================
    /// Functions - Internal
    /// =====================================================

    /// @inheritdoc MessageReceiverBase
    function _onMessageReceive(
        bytes32 messageType,
        uint256 sourceChainNonce,
        bytes memory message
    ) internal virtual override {
        if (messageType == MessageTypes.LST_BACKING_MESSAGE_TYPE) {
            MessageTypes.LstBackingMessage memory info = abi.decode(message, (MessageTypes.LstBackingMessage));
            _trackPerTokenOnMessageReceive(info.token, info.ethPerToken, info.timestamp, sourceChainNonce);
        } else {
            revert Errors.UnsupportedMessage(messageType, message);
        }
    }

    /// @dev Handles `LST_BACKING_MESSAGE_TYPE` messages
    function _trackPerTokenOnMessageReceive(
        address token,
        uint208 amount,
        uint48 timestamp,
        uint256 sourceChainNonce
    ) internal {
        if (!registered[token]) {
            revert UnsupportedToken(token);
        }

        // Message may be retried but if the message is older than one we've already
        // processed we don't want to accept it
        if (sourceChainNonce <= lastStoredNonce) {
            emit StaleNonce(token, lastStoredNonce, sourceChainNonce);
            return;
        }

        lastStoredNonce = sourceChainNonce;

        emit EthPerTokenUpdated(token, amount, timestamp);

        trackedTokens[token] = TokenTrack({ ethPerToken: amount, lastSetTimestamp: timestamp });
    }
}
