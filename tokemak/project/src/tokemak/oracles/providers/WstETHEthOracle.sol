// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IstEth } from "src/tokemak/interfaces/external/lido/IstEth.sol";
import { IwstEth } from "src/tokemak/interfaces/external/lido/IwstEth.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";

/// @title Price oracle specifically for wstETH
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract WstETHEthOracle is SystemComponent, IPriceOracle {
    IwstEth public immutable wstETH;
    IstEth public immutable stETH;
    uint256 public immutable stETHPrecision;

    error InvalidDecimals(address token, uint8 decimals);

    constructor(ISystemRegistry _systemRegistry, address _wstETH) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");

        Errors.verifyNotZero(address(_wstETH), "_wstETH");

        wstETH = IwstEth(_wstETH);

        address stETHAddress = wstETH.stETH();
        Errors.verifyNotZero(stETHAddress, "stETHAddress");

        stETH = IstEth(stETHAddress);
        uint8 stETHDecimals = stETH.decimals();

        if (stETHDecimals == 0) {
            revert InvalidDecimals(stETHAddress, stETHDecimals);
        }
        stETHPrecision = 10 ** stETHDecimals;
    }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "wstEthEth";
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(
        address token
    ) external returns (uint256 price) {
        // This oracle is only setup to handle a single token but could possibly be
        // configured incorrectly at the root level and receive others to price.

        if (token != address(wstETH)) {
            revert Errors.InvalidToken(token);
        }

        uint256 stETHPrice = systemRegistry.rootPriceOracle().getPriceInEth(address(stETH));

        // Our prices are always in 1e18 so just use steths precision to get back to 1e18;
        price = (stETH.getPooledEthByShares(1 ether) * stETHPrice) / stETHPrecision;
    }
}
