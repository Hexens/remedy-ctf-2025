// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

/// @title Base Stats Calculator
/// @notice Captures common behavior across all calculators
/// @dev Performs security checks and general roll-up behavior
abstract contract BaseStatsCalculator is IStatsCalculator, SecurityBase, SystemComponent, Initializable {
    modifier onlyStatsSnapshot() {
        if (!_hasRole(Roles.STATS_SNAPSHOT_EXECUTOR, msg.sender)) {
            revert Errors.MissingRole(Roles.STATS_SNAPSHOT_EXECUTOR, msg.sender);
        }
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        _disableInitializers();
    }

    /// @inheritdoc IStatsCalculator
    function snapshot() external override onlyStatsSnapshot {
        if (!shouldSnapshot()) {
            revert NoSnapshotTaken();
        }
        _snapshot();
    }

    /// @notice Capture stat data about this setup
    /// @dev This is protected by the STATS_SNAPSHOT_EXECUTOR
    function _snapshot() internal virtual;

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view virtual returns (bool takeSnapshot);
}
