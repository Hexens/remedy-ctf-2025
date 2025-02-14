// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IeETH } from "src/tokemak/interfaces/external/etherfi/IeETH.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";

contract EethLSTCalculator is LSTCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return IeETH(lstTokenAddress).liquidityPool().amountForShare(1 ether);
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return true;
    }
}
