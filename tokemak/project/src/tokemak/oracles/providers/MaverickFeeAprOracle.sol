// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IMaverickFeeAprOracle } from "src/tokemak/interfaces/oracles/IMaverickFeeAprOracle.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

contract MaverickFeeAprOracle is SystemComponent, SecurityBase, IMaverickFeeAprOracle {
    struct FeeAprData {
        uint216 feeApr;
        uint40 timestamp;
    }

    uint256 public maxFeeAprLatency;
    uint256 public constant MAX_FEE_APR = 365e18; // cap feeApr at 365% as a sanity check

    mapping(address => FeeAprData) public feeAprDataMapping;

    error BoostedPositionFeeAprNotSet();
    error BoostedPositionFeeAprExpired();
    error InvalidMaxFeeAprLatency();
    error TimestampOlderThanCurrent(address boostedPosition, uint256 queriedTimestamp);
    error CannotSetFeeAprAboveMax(uint256 proposedFeeApr, uint256 maxFeeApr);
    error CannotWriteAnOlderValue();

    event FeeAprSet(address boostedPosition, uint256 feeApr, uint256 queriedTimestamp);
    event MaxFeeAprLatencySet(uint256 _maxFeeAprLatency);

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        maxFeeAprLatency = 7 days;
    }

    /// @inheritdoc IMaverickFeeAprOracle
    function setFeeApr(
        address boostedPosition,
        uint256 feeApr,
        uint256 queriedTimestamp
    ) external hasRole(Roles.MAVERICK_FEE_ORACLE_EXECUTOR) {
        // feeApr can be zero because there can be no swaps in the recent past
        // slither-disable-next-line timestamp
        if (queriedTimestamp > block.timestamp) {
            revert TimestampOlderThanCurrent(boostedPosition, queriedTimestamp);
        }

        if (feeApr > MAX_FEE_APR) {
            revert CannotSetFeeAprAboveMax(feeApr, MAX_FEE_APR);
        }
        if (queriedTimestamp < feeAprDataMapping[boostedPosition].timestamp) {
            revert CannotWriteAnOlderValue();
        }

        feeAprDataMapping[boostedPosition] = FeeAprData(uint216(feeApr), uint40(queriedTimestamp));
        emit FeeAprSet(boostedPosition, feeApr, queriedTimestamp);
    }

    /// @inheritdoc IMaverickFeeAprOracle
    function getFeeApr(
        address boostedPosition
    ) external view returns (uint256 feeApr) {
        FeeAprData memory data = feeAprDataMapping[boostedPosition];
        // slither-disable-next-line incorrect-equality,timestamp
        if (data.timestamp == 0) revert BoostedPositionFeeAprNotSet();
        // slither-disable-next-line timestamp
        if (block.timestamp > (uint256(data.timestamp) + maxFeeAprLatency)) revert BoostedPositionFeeAprExpired();

        feeApr = uint256(data.feeApr);
    }

    function _setMaxFeeAprLatency(
        uint256 _maxFeeAprLatency
    ) private {
        Errors.verifyNotZero(_maxFeeAprLatency, "_maxFeeAprLatency");
        if (_maxFeeAprLatency > type(uint32).max) {
            revert InvalidMaxFeeAprLatency();
        }
        maxFeeAprLatency = _maxFeeAprLatency;
        emit MaxFeeAprLatencySet(_maxFeeAprLatency);
    }

    /// @inheritdoc IMaverickFeeAprOracle
    function setMaxFeeAprLatency(
        uint256 _maxFeeAprLatency
    ) external hasRole(Roles.ORACLE_MANAGER) {
        _setMaxFeeAprLatency(_maxFeeAprLatency);
    }
}
