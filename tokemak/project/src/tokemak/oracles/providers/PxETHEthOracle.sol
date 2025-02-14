// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { IAutoPxEth } from "src/tokemak/interfaces/external/pirex/IAutoPxEth.sol";

/// @title Price oracle specifically for pxETH
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract PxETHEthOracle is SystemComponent, IPriceOracle {
    IAutoPxEth public immutable apxETH;
    address public immutable pxETH;

    constructor(ISystemRegistry _systemRegistry, address _apxETH, address _pxETH) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");

        Errors.verifyNotZero(_apxETH, "_apxETH");

        Errors.verifyNotZero(_pxETH, "_pxETH");

        apxETH = IAutoPxEth(_apxETH);

        pxETH = apxETH.asset();

        if (_pxETH != pxETH) revert Errors.InvalidAddress(_pxETH);
    }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "pxETH";
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(
        address token
    ) external returns (uint256 price) {
        // This oracle is only setup to handle a single token but could possibly be
        // configured incorrectly at the root level and receive others to price.

        if (token != pxETH) {
            revert Errors.InvalidToken(token);
        }

        price = (systemRegistry.rootPriceOracle().getPriceInEth(address(apxETH)) * 1e18) / apxETH.assetsPerShare();
    }
}
