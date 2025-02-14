// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";
import { IStakedTokenV1 } from "src/tokemak/interfaces/external/coinbase/IStakedTokenV1.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

contract CbethLSTCalculator is LSTCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return IStakedTokenV1(lstTokenAddress).exchangeRate();
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }
}
