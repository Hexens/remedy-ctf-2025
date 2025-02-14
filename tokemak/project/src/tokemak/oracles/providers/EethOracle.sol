// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IeETH } from "src/tokemak/interfaces/external/etherfi/IeETH.sol";
import { IweETH } from "src/tokemak/interfaces/external/etherfi/IweETH.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";

/// @title Price oracle specifically for eETH
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract EethOracle is SystemComponent, IPriceOracle {
    IweETH public immutable weETH;
    IeETH public immutable eETH;

    error InvalidDecimals(address token, uint8 decimals);

    constructor(ISystemRegistry _systemRegistry, address _weETH) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");

        Errors.verifyNotZero(address(_weETH), "_weETH");

        weETH = IweETH(_weETH);

        eETH = weETH.eETH();
        Errors.verifyNotZero(address(eETH), "eETH");

        if (eETH.decimals() != 18) {
            revert InvalidDecimals(address(eETH), eETH.decimals());
        }
        if (weETH.decimals() != 18) {
            revert InvalidDecimals(address(weETH), weETH.decimals());
        }
    }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure returns (string memory) {
        return "eeth";
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(
        address token
    ) external returns (uint256 price) {
        // This oracle is only setup to handle a single token but could possibly be
        // configured incorrectly at the root level and receive others to price.

        if (token != address(eETH)) {
            revert Errors.InvalidToken(token);
        }

        uint256 weETHPrice = systemRegistry.rootPriceOracle().getPriceInEth(address(weETH));

        price = (weETHPrice * 1e18) / weETH.getEETHByWeETH(1e18);
    }
}
