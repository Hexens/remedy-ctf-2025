// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";
import { IstEth } from "src/tokemak/interfaces/external/lido/IstEth.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

contract StethLSTCalculator is LSTCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return IstEth(lstTokenAddress).getPooledEthByShares(1 ether);
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return true;
    }
}
