// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { AuraCalculator } from "src/tokemak/stats/calculators/AuraCalculator.sol";
import { IBoosterLite } from "src/tokemak/interfaces/external/aura/IBoosterLite.sol";

contract AuraL2Calculator is AuraCalculator {
    constructor(ISystemRegistry _systemRegistry, address _booster) AuraCalculator(_systemRegistry, _booster) { }

    /// @inheritdoc AuraCalculator
    function getPlatformTokenMintAmount(address, uint256 _annualizedReward) public view override returns (uint256) {
        return IBoosterLite(BOOSTER).minter().mintRate() * _annualizedReward / 1e18;
    }
}
