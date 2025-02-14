// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { BalancerStablePoolCalculatorBase } from "src/tokemak/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";

contract BalancerMetaStablePoolCalculator is BalancerStablePoolCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry,
        address _balancerVault
    ) BalancerStablePoolCalculatorBase(_systemRegistry, _balancerVault) { }

    function getVirtualPrice() internal view override returns (uint256 virtualPrice) {
        virtualPrice = BalancerUtilities._getMetaStableVirtualPrice(balancerVault, poolAddress);
    }

    function getPoolTokens() internal view override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (tokens, balances) = BalancerUtilities._getPoolTokens(balancerVault, poolAddress);
    }
}
