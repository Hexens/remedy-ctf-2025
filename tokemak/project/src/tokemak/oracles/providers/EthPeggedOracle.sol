// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";

/// @title Price oracle for tokens we want to configure 1:1 to ETH. WETH for example
/// @dev getPriceEth is not a view fn to support reentrancy checks. Doesn't actually change state.
contract EthPeggedOracle is SystemComponent, IPriceOracle {
    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) { }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "ethPegged";
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(
        address
    ) external pure returns (uint256 price) {
        price = 1e18;
    }
}
