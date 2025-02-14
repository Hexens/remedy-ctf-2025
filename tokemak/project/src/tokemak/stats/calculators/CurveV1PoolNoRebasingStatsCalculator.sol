// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { CurvePoolNoRebasingCalculatorBase } from "src/tokemak/stats/calculators/base/CurvePoolNoRebasingCalculatorBase.sol";
import { ICurveV1StableSwap } from "src/tokemak/interfaces/external/curve/ICurveV1StableSwap.sol";

/// @title Curve V1 Pool No Rebasing
/// @notice Calculate stats for a Curve V1 StableSwap pool
/// @dev If used with an ETH pool, ensure it isn't an older one with reentrancy issue
contract CurveV1PoolNoRebasingStatsCalculator is CurvePoolNoRebasingCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) CurvePoolNoRebasingCalculatorBase(_systemRegistry) { }

    function getVirtualPrice() internal view override returns (uint256 virtualPrice) {
        return ICurveV1StableSwap(poolAddress).get_virtual_price();
    }
}
