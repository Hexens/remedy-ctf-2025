// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IAccessController } from "src/tokemak/interfaces/security/IAccessController.sol";
import { AccessControlEnumerable } from "openzeppelin-contracts/access/AccessControlEnumerable.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";

contract AccessController is SystemComponent, AccessControlEnumerable, IAccessController {
    // ------------------------------------------------------------
    //          Pre-initialize roles list for deployer
    // ------------------------------------------------------------
    constructor(
        address _systemRegistry
    ) SystemComponent(ISystemRegistry(_systemRegistry)) {
        Errors.verifyNotZero(_systemRegistry, "systemRegistry");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(Roles.REBALANCER, msg.sender);
        _setupRole(Roles.AUTO_POOL_FACTORY_VAULT_CREATOR, msg.sender);
    }

    // ------------------------------------------------------------
    //               Role management methods
    // ------------------------------------------------------------
    /// @inheritdoc IAccessController
    function setupRole(bytes32 role, address account) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessDenied();
        }

        // only do if role is not registered already
        if (!hasRole(role, account)) {
            _setupRole(role, account);
        }
    }

    /// @inheritdoc IAccessController
    function verifyOwner(
        address account
    ) public view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, account)) {
            revert AccessDenied();
        }
    }
}
