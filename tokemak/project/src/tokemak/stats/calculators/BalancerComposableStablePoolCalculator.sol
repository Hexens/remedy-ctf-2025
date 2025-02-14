// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerStablePoolCalculatorBase } from "src/tokemak/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";

contract BalancerComposableStablePoolCalculator is BalancerStablePoolCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry,
        address _balancerVault
    ) BalancerStablePoolCalculatorBase(_systemRegistry, _balancerVault) { }

    function getVirtualPrice() internal view override returns (uint256 virtualPrice) {
        virtualPrice = IBalancerComposableStablePool(poolAddress).getRate();
    }

    function getPoolTokens() internal view override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (tokens, balances) = BalancerUtilities._getComposablePoolTokensSkipBpt(balancerVault, poolAddress);
    }

    function _isExemptFromYieldProtocolFee() internal view override returns (bool) {
        for (uint256 i = 0; i < numTokens; ++i) {
            // for simplicity, if one token is exempt we treat it like all tokens are exempt. This is fine because
            // the return will show up in either baseApr or feeApr. This just makes sure it goes to the right bucket
            if (IBalancerComposableStablePool(poolAddress).isTokenExemptFromYieldProtocolFee(reserveTokens[i])) {
                return true;
            }
        }
        // if all are non-exempt, then return false
        return false;
    }
}
