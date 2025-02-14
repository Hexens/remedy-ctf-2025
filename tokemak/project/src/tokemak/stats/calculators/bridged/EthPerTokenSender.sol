// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { MessageTypes } from "src/tokemak/libs/MessageTypes.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SafeCast } from "openzeppelin-contracts/utils/math/SafeCast.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { IMessageProxy } from "src/tokemak/interfaces/messageProxy/IMessageProxy.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";

/// @notice Sends the result of `calculateEthPerToken()` for each registered LST calculator to other chains
contract EthPerTokenSender is SystemComponent, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// =====================================================
    /// Internal Vars
    /// =====================================================

    /// @notice Calculators that are configured to send data
    /// @dev Exposed via getCalculators()
    EnumerableSet.AddressSet internal _calculators;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Last sent value for a calculator
    /// @dev calculator -> (ethPerToken, lastSentTimestamp)
    mapping(address => TokenTrack) public lastValue;

    /// @notice Max elapsed seconds before we'll send a value even if unchanged
    uint256 public heartbeat;

    /// =====================================================
    /// Events
    /// =====================================================

    event CalculatorsRegistered(bytes32[] calculators);
    event CalculatorsUnregistered(address[] calculators);
    event HeartbeatSet(uint256 newHeartbeat);

    /// =====================================================
    /// Errors
    /// =====================================================

    error InvalidCalculator(address calculator);
    error SendNotRequired(address calculator);

    /// =====================================================
    /// Structs
    /// =====================================================

    struct TokenTrack {
        uint208 ethPerToken;
        uint48 lastSentTimestamp;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        _setHeartbeat(2 days);
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Get the latest ethPerToken for the specified calculators and send to other chains
    /// @param calculators Calculators to query
    function execute(
        address[] memory calculators
    ) external hasRole(Roles.STATS_LST_ETH_TOKEN_EXECUTOR) {
        uint256 len = calculators.length;
        Errors.verifyNotZero(len, "len");

        IMessageProxy messageProxy = systemRegistry.messageProxy();
        Errors.verifyNotZero(address(messageProxy), "messageProxy");
        uint256 maxTime = heartbeat;

        for (uint256 i = 0; i < len;) {
            address calculator = calculators[i];
            if (!_calculators.contains(calculator)) {
                revert InvalidCalculator(calculator);
            }

            uint256 currentEthPerToken = LSTCalculatorBase(calculator).calculateEthPerToken();

            if (!_shouldSend(currentEthPerToken, maxTime, lastValue[calculator])) {
                revert SendNotRequired(calculator);
            }

            TokenTrack memory newValues = TokenTrack({
                ethPerToken: SafeCast.toUint208(currentEthPerToken),
                lastSentTimestamp: uint48(block.timestamp)
            });

            // slither-disable-next-line reentrancy-no-eth
            lastValue[calculator] = newValues;
            address lst = LSTCalculatorBase(calculator).lstTokenAddress();

            bytes memory message = encodeMessage(lst, newValues.ethPerToken, newValues.lastSentTimestamp);

            // slither-disable-next-line reentrancy-benign
            messageProxy.sendMessage(MessageTypes.LST_BACKING_MESSAGE_TYPE, message);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Checks latest ethPerToken against last sent value to determine if a message should be sent
    /// @dev Meant to be called off-chain
    /// @param skip Number of calculators to skip when iterating the list
    /// @param take Number of calculators to evaluate when iterating the list. Pass uint256.max for all
    /// @return data Address of calculators to send
    function shouldSend(uint256 skip, uint256 take) external view returns (address[] memory data) {
        take = _validateSkipTake(skip, take);

        address[] memory results = new address[](take);
        uint256 maxTime = heartbeat;
        uint256 r = 0;
        for (uint256 i = 0; i < take; ++i) {
            address calculator = _calculators.at(skip + i);
            uint256 currentValue = LSTCalculatorBase(calculator).calculateEthPerToken();
            TokenTrack memory lastValues = lastValue[calculator];

            // slither-disable-next-line timestamp
            if (_shouldSend(currentValue, maxTime, lastValues)) {
                results[r] = calculator;
                ++r;
            }
        }

        data = new address[](r);
        for (uint256 i = 0; i < r; ++i) {
            data[i] = results[i];
        }
    }

    /// @notice Set the max elapsed seconds before we'll send a value even if unchanged
    /// @param newHeartbeat New value to set
    function setHeartbeat(
        uint256 newHeartbeat
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        _setHeartbeat(newHeartbeat);
    }

    /// @notice Add calculators that should send their data to other chains
    /// @param calculators The apr id's of the calculators to add
    function registerCalculators(
        bytes32[] memory calculators
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        uint256 len = calculators.length;
        Errors.verifyNotZero(len, "len");

        IStatsCalculatorRegistry calcRegistry = systemRegistry.statsCalculatorRegistry();

        for (uint256 i = 0; i < len;) {
            IStatsCalculator calculator = calcRegistry.getCalculator(calculators[i]);

            // If we passed in unnecessary data revert so we can figure out why
            if (!_calculators.add(address(calculator))) {
                revert Errors.AlreadyRegistered(address(calculator));
            }
            unchecked {
                ++i;
            }
        }

        emit CalculatorsRegistered(calculators);
    }

    /// @notice Removes calculators that have already been added
    /// @param calculators Addresses of the calculators to remove
    function unregisterCalculators(
        address[] memory calculators
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        uint256 len = calculators.length;
        Errors.verifyNotZero(len, "len");

        for (uint256 i = 0; i < len;) {
            // If we passed in unnecessary data revert so we can figure out why
            if (!_calculators.remove(calculators[i])) {
                revert Errors.NotRegistered();
            }
            unchecked {
                ++i;
            }
        }

        emit CalculatorsUnregistered(calculators);
    }

    /// @notice Returns all currently registered calculators
    function getCalculators() external view returns (address[] memory data) {
        uint256 len = _calculators.length();
        data = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            data[i] = _calculators.at(i);
        }
    }

    /// =====================================================
    /// Functions - Public
    /// =====================================================

    /// @notice Encode the message to be sent
    /// @param lst Address of the LST token the message represents
    /// @param ethPerToken Current value of the `calculateEthPerToken()` call
    /// @param lastSentTimestamp Timestamp of call
    function encodeMessage(
        address lst,
        uint208 ethPerToken,
        uint48 lastSentTimestamp
    ) public pure returns (bytes memory) {
        return abi.encode(
            MessageTypes.LstBackingMessage({ token: lst, ethPerToken: ethPerToken, timestamp: lastSentTimestamp })
        );
    }

    /// =====================================================
    /// Functions - Internal
    /// =====================================================

    function _shouldSend(
        uint256 currentEthPerToken,
        uint256 maxTime,
        TokenTrack memory oldValues
    ) internal view returns (bool) {
        // slither-disable-next-line timestamp
        return currentEthPerToken != oldValues.ethPerToken || oldValues.lastSentTimestamp + maxTime < block.timestamp;
    }

    /// @dev Sanitize skip and take parameters for the calculator list
    function _validateSkipTake(uint256 skip, uint256 take) internal view returns (uint256 takeRet) {
        uint256 len = _calculators.length();
        if (take == type(uint256).max) {
            take = len;
        }
        if (skip >= len) {
            revert Errors.InvalidParam("skip");
        }
        if (skip + take > len) {
            takeRet = len - skip;
        } else {
            takeRet = take;
        }
    }

    function _setHeartbeat(
        uint256 newHeartbeat
    ) internal {
        Errors.verifyNotZero(newHeartbeat, "newHeartbeat");

        // Sanity Check
        if (newHeartbeat > 30 days) {
            revert Errors.InvalidParam("newHeartbeat");
        }

        heartbeat = newHeartbeat;

        emit HeartbeatSet(newHeartbeat);
    }
}
