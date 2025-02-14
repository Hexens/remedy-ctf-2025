// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";
import { IswETH } from "src/tokemak/interfaces/external/swell/IswETH.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

contract SwethLSTCalculator is LSTCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return IswETH(lstTokenAddress).swETHToETHRate();
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }
}
