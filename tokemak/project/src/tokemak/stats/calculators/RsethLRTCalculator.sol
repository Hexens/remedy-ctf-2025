// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IRSETH } from "src/tokemak/interfaces/external/kelpdao/IRSETH.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ILRTOracle } from "src/tokemak/interfaces/external/kelpdao/ILRTOracle.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";

contract RsethLRTCalculator is LSTCalculatorBase {
    /// @notice Constant key for getting oracle address from KelpDAO LRTConfig contract.
    bytes32 public constant LRT_ORACLE = keccak256("LRT_ORACLE");

    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }

    /// @inheritdoc LSTCalculatorBase
    /// @dev If rsEth totalSupply is 0, returns 1e18
    function calculateEthPerToken() public view override returns (uint256) {
        return ILRTOracle(IRSETH(lstTokenAddress).lrtConfig().getContract(LRT_ORACLE)).rsETHPrice();
    }
}
