// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Ops Ltd. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ICryptoSwapPool } from "src/tokemak/interfaces/external/curve/ICryptoSwapPool.sol";
import { CurvePoolNoRebasingCalculatorBase } from "src/tokemak/stats/calculators/base/CurvePoolNoRebasingCalculatorBase.sol";

/// @title Curve V2 Pool No Rebasing with reentrancy protection
/// @notice Calculate stats for a Curve V2 CryptoSwap pool
contract CurveV2PoolNoRebasingStatsCalculator is CurvePoolNoRebasingCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) CurvePoolNoRebasingCalculatorBase(_systemRegistry) { }

    function getVirtualPrice() internal override returns (uint256 virtualPrice) {
        ICryptoSwapPool(poolAddress).claim_admin_fees();
        return ICryptoSwapPool(poolAddress).get_virtual_price();
    }
}
