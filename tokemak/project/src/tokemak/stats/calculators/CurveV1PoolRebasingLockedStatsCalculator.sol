// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Ops Ltd. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ICurveV1StableSwap } from "src/tokemak/interfaces/external/curve/ICurveV1StableSwap.sol";
import { CurvePoolRebasingCalculatorBase } from "src/tokemak/stats/calculators/base/CurvePoolRebasingCalculatorBase.sol";

/// @title Curve V1 Pool With Rebasing Tokens that does not require reentrancy protection
/// @notice Calculate stats for a Curve V1 StableSwap pool
contract CurveV1PoolRebasingLockedStatsCalculator is CurvePoolRebasingCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) CurvePoolRebasingCalculatorBase(_systemRegistry) { }

    function getVirtualPrice() internal view override returns (uint256 virtualPrice) {
        virtualPrice = ICurveV1StableSwap(poolAddress).get_virtual_price();
    }
}
