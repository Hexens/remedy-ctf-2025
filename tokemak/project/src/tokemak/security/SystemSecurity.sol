// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ISystemSecurity } from "src/tokemak/interfaces/security/ISystemSecurity.sol";
import { TransientStorage } from "src/tokemak/libs/TransientStorage.sol";

/**
 * @notice Cross-contract system-level functionality around pausing and various security features.
 * Allows us to pause all pausable contracts in the system
 * Ensures that operations that change NAV and those that don't are not mixed in the same transaction.
 */
abstract contract SystemSecurity is SystemComponent, SecurityBase, ISystemSecurity {
    bool internal _systemPaused = false;

    event SystemPaused(address account);
    event SystemUnpaused(address account);

    error SystemAlreadyPaused();
    error SystemNotPaused();

    uint256 private constant _ALLOWED_AUTOPOOL = uint256(keccak256(bytes("_ALLOWED_AUTOPOOL"))) - 1;

    /// @notice How many NAV/share changing operations are in progress in the system
    uint256 private _navOpsInProgress = 0;

    modifier onlyAutopool() {
        if (!systemRegistry.autoPoolRegistry().isVault(msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    modifier onlyAutopoolRouter() {
        if ((address(systemRegistry.autoPoolRouter()) != msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc ISystemSecurity
    /// @dev This is function is used as guard to prevent malicious calls from user payloads into a different autopool
    /// via the AutopilotRouter
    function navOpsInProgress() external view returns (uint256) {
        if (TransientStorage.dataExists(_ALLOWED_AUTOPOOL)) {
            address autopool = abi.decode(TransientStorage.getBytes(_ALLOWED_AUTOPOOL), (address));
            if (autopool != msg.sender) {
                revert Errors.AccessDenied();
            }
        }
        return _navOpsInProgress;
    }

    /// @inheritdoc ISystemSecurity
    /// @notice Enters a NAV/share changing operation from an Autopool
    function enterNavOperation() external override onlyAutopool {
        ++_navOpsInProgress;
    }

    /// @inheritdoc ISystemSecurity
    /// @notice Exits a NAV/share changing operation from an Autopool
    function exitNavOperation() external override onlyAutopool {
        --_navOpsInProgress;
    }

    /// @notice Pause every pausable contract in the system
    /// @dev Reverts if already paused or not EMERGENCY_PAUSER role
    function pauseSystem() external hasRole(Roles.EMERGENCY_PAUSER) {
        if (_systemPaused) {
            revert SystemAlreadyPaused();
        }
        _systemPaused = true;

        emit SystemPaused(msg.sender);
    }

    /// @notice Unpause every pausable contract in the system that isn't explicitly paused
    /// @dev Reverts if system not paused or not EMERGENCY_PAUSER role.
    function unpauseSystem() external hasRole(Roles.EMERGENCY_PAUSER) {
        if (!_systemPaused) {
            revert SystemNotPaused();
        }
        _systemPaused = false;

        emit SystemUnpaused(msg.sender);
    }

    /// @inheritdoc ISystemSecurity
    function setAllowedAutopool(
        address autopool
    ) external onlyAutopoolRouter {
        if (TransientStorage.dataExists(_ALLOWED_AUTOPOOL)) {
            revert Errors.AccessDenied();
        }

        TransientStorage.setBytes(abi.encode(autopool), _ALLOWED_AUTOPOOL);
    }

    /// @inheritdoc ISystemSecurity
    function clearAllowedAutopool() external onlyAutopoolRouter {
        TransientStorage.clearBytes(_ALLOWED_AUTOPOOL);
    }
}
