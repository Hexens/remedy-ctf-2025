// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

contract SystemComponent is ISystemComponent {
    ISystemRegistry internal immutable systemRegistry;

    constructor(
        ISystemRegistry _systemRegistry
    ) {
        Errors.verifyNotZero(address(_systemRegistry), "_systemRegistry");
        systemRegistry = _systemRegistry;
    }

    /// @inheritdoc ISystemComponent
    function getSystemRegistry() external view returns (address) {
        return address(systemRegistry);
    }
}
