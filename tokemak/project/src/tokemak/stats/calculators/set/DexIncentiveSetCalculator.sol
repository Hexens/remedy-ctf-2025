// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { BaseSetCalculator } from "src/tokemak/stats/calculators/set/BaseSetCalculator.sol";
import { StatsTransientCacheStore } from "src/tokemak/stats/calculators/set/StatsTransientCacheStore.sol";

contract DexIncentiveSetCalculator is BaseSetCalculator, IDexLSTStats {
    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseSetCalculator(_systemRegistry) { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @inheritdoc IDexLSTStats
    function current() external view returns (DexLSTStatsData memory result) {
        bytes32 aprId = getAprId;
        StatsTransientCacheStore _cacheStore = cacheStore;

        if (_cacheStore.hasTransient(aprId)) {
            result = abi.decode(_cacheStore.getTransient(aprId), (DexLSTStatsData));
        }

        // Intentionally returns empty result
    }
}
