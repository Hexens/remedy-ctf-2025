// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IETHx } from "src/tokemak/interfaces/external/stader/IETHx.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStaderOracle } from "src/tokemak/interfaces/external/stader/IStaderOracle.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";

contract ETHxLSTCalculator is LSTCalculatorBase {
    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        IETHx token = IETHx(lstTokenAddress);
        IStaderOracle.ExchangeRate memory exchangeRateInfo = token.staderConfig().getStaderOracle().getExchangeRate();
        return exchangeRateInfo.totalETHXSupply == 0
            ? 1e18
            : exchangeRateInfo.totalETHBalance * 1e18 / exchangeRateInfo.totalETHXSupply;
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }
}
