// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Stats } from "src/tokemak/stats/Stats.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { MessageReceiverBase } from "src/tokemak/receivingRouter/MessageReceiverBase.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";
import { EthPerTokenStore } from "src/tokemak/stats/calculators/bridged/EthPerTokenStore.sol";
import { MessageTypes } from "src/tokemak/libs/MessageTypes.sol";

/// @notice Tracks LSTs that are bridged from another chain
/// @dev Snapshot still required
contract BridgedLSTCalculator is LSTCalculatorBase, MessageReceiverBase {
    /// =====================================================
    /// Internal Vars
    /// =====================================================

    /// @notice Whether `lstTokenAddress` is a rebasing token
    bool internal _usePriceAsDiscount;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Whether this calculator has received its first base apr reading
    bool public firstBaseAprReceived;

    /// @notice Lookup of current eth/token values
    EthPerTokenStore public ethPerTokenStore;

    /// @notice Address of corresponding token on source chain
    address public sourceTokenAddress;

    /// @notice Stored nonce sent from source chain
    uint256 public lastStoredNonce;

    /// =====================================================
    /// Events
    /// =====================================================

    event EthPerTokenStoreSet(address store);

    /// =====================================================
    /// Failure Events
    /// =====================================================

    /// @notice Emitted when a stale nonce is sent across from source chain
    event StaleNonce(uint256 lastStoredNonce, uint256 newSourceChainNonce);

    /// =====================================================
    /// Structs
    /// =====================================================

    struct L2InitData {
        address lstTokenAddress;
        address sourceTokenAddress;
        bool usePriceAsDiscount;
        address ethPerTokenStore;
    }

    /// =====================================================
    /// Functions - Constructor/Initializer
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes memory initData) public virtual override initializer {
        L2InitData memory decodedInitData = abi.decode(initData, (L2InitData));

        Errors.verifyNotZero(decodedInitData.lstTokenAddress, "lstTokenAddress");
        Errors.verifyNotZero(decodedInitData.sourceTokenAddress, "sourceTokenAddress");

        lstTokenAddress = decodedInitData.lstTokenAddress;
        _aprId = Stats.generateRawTokenIdentifier(decodedInitData.lstTokenAddress);
        _usePriceAsDiscount = decodedInitData.usePriceAsDiscount;
        sourceTokenAddress = decodedInitData.sourceTokenAddress;

        _setEthPerTokenStore(EthPerTokenStore(decodedInitData.ethPerTokenStore));
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Update the contract used to lookup bridged eth/token values
    /// @param newStore New lookup contract
    function setEthPerTokenStore(
        EthPerTokenStore newStore
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        _setEthPerTokenStore(newStore);
    }

    /// @notice Switches flag for sending messages to other chains.
    /// @dev This is a receiving contract, does not send
    function setDestinationMessageSend() external virtual override {
        revert Errors.NotSupported();
    }

    /// =====================================================
    /// Functions - Public
    /// =====================================================

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view virtual override returns (bool) {
        if (firstBaseAprReceived) {
            return super.shouldSnapshot();
        } else {
            return false;
        }
    }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view virtual override returns (uint256) {
        // Get the backing number we track separate from the LST Base APR numbers we get
        (uint256 storedValue, uint256 storedTimestamp) = ethPerTokenStore.getEthPerToken(sourceTokenAddress);

        // If the value we received from the LST Base APR message is newer than
        // the one we track globally, then use it
        // slither-disable-next-line timestamp
        if (lastBaseAprSnapshotTimestamp >= storedTimestamp) {
            return lastBaseAprEthPerToken;
        }

        // Otherwise, use the global one.
        return storedValue;
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public view virtual override returns (bool) {
        return _usePriceAsDiscount;
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
        if (messageType == MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE) {
            MessageTypes.LSTDestinationInfo memory info = abi.decode(message, (MessageTypes.LSTDestinationInfo));
            _snapshotOnMessageReceive(
                info.currentEthPerToken, info.snapshotTimestamp, info.newBaseApr, sourceChainNonce
            );
        } else {
            revert Errors.UnsupportedMessage(messageType, message);
        }
    }

    /// @notice Handles an `LST_SNAPSHOT_MESSAGE_TYPE` message
    /// @dev This message can be received multiple times (retries/re-sends), make sure sure the stats and such handle
    /// that. Multiple events fired are OK
    function _snapshotOnMessageReceive(
        uint256 currentEthPerToken,
        uint256 snapshotTimestamp,
        uint256 newBaseApr,
        uint256 sourceChainNonce
    ) internal {
        // Message may be retried but if the message is older than one we've already
        // processed we don't want to accept it. The send in the same block on the source chain
        // slither-disable-next-line timestamp
        if (sourceChainNonce <= lastStoredNonce) {
            emit StaleNonce(lastStoredNonce, sourceChainNonce);
            return;
        }

        lastStoredNonce = sourceChainNonce;

        emit BaseAprSnapshotTaken(
            lastBaseAprEthPerToken,
            lastBaseAprSnapshotTimestamp,
            currentEthPerToken,
            snapshotTimestamp,
            baseApr,
            newBaseApr
        );

        baseApr = newBaseApr;
        lastBaseAprEthPerToken = currentEthPerToken;
        lastBaseAprSnapshotTimestamp = snapshotTimestamp;

        // Since discount information doesn't have any value when base apr is zero
        // we're forcing ourselves to have received a base apr reading first before evaluating
        // the others. Simplifies the initialization of the calculator a bit
        if (firstBaseAprReceived) {
            _snapshot();
        } else {
            firstBaseAprReceived = true;

            updateDiscountHistory(currentEthPerToken);
            updateDiscountTimestampByPercent();
        }
    }

    function _setEthPerTokenStore(
        EthPerTokenStore newStore
    ) internal {
        Errors.verifyNotZero(address(newStore), "newStore");

        ethPerTokenStore = newStore;

        emit EthPerTokenStoreSet(address(newStore));
    }

    /// @dev APR snapshots are triggered via messages so timing isn't required
    function _timeForAprSnapshot() internal view virtual override returns (bool) {
        return false;
    }
}
