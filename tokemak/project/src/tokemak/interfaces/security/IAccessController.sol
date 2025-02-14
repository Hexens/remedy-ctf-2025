// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAccessControlEnumerable } from "openzeppelin-contracts/access/IAccessControlEnumerable.sol";

interface IAccessController is IAccessControlEnumerable {
    error AccessDenied();

    /**
     * @notice Setup a role for an account
     * @param role The role to setup
     * @param account The account to setup the role for
     */
    function setupRole(bytes32 role, address account) external;

    /**
     * @notice Verify if an account is an owner. Reverts if not
     * @param account The account to verify
     */
    function verifyOwner(
        address account
    ) external view;
}
