// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { StatsTransientCacheStore } from "src/tokemak/stats/calculators/set/StatsTransientCacheStore.sol";

/// @notice Base for transient storage based calculators
abstract contract BaseSetCalculator is SystemComponent, Initializable, IStatsCalculator {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    // @notice Version for this type of calculator
    uint256 public constant VERSION = 2;

    /// @notice Type of calculator;
    string public calcType;

    /// @notice Store for set calc data
    StatsTransientCacheStore public cacheStore;

    /// @inheritdoc IStatsCalculator
    bytes32 public getAprId;

    /// @inheritdoc IStatsCalculator
    address public getAddressId;

    /// =====================================================
    /// Private Vars
    /// =====================================================

    /// @notice Actual calculators this calculator needs to reference
    /// @dev Exposed via baseCalculators()
    address[] private _baseCalculators;

    /// =====================================================
    /// Structs
    /// =====================================================

    struct InitData {
        address addressId;
        address[] baseCalculators;
        address cacheStore;
        bytes32 aprId;
        string calcType;
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) {
        _disableInitializers();
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    function initialize(bytes32[] calldata, bytes memory initData) external virtual initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.addressId, "addressId");
        Errors.verifyNotZero(decodedInitData.cacheStore, "cacheStore");
        Errors.verifyNotZero(decodedInitData.aprId, "aprId");
        Errors.verifyNotZero(bytes(decodedInitData.calcType).length, "calcType");

        getAddressId = decodedInitData.addressId;
        _baseCalculators = decodedInitData.baseCalculators;
        cacheStore = StatsTransientCacheStore(decodedInitData.cacheStore);

        getAprId = decodedInitData.aprId;
        calcType = decodedInitData.calcType;

        address cacheStoreRegistry = StatsTransientCacheStore(decodedInitData.cacheStore).getSystemRegistry();
        if (address(systemRegistry) != cacheStoreRegistry) {
            revert Errors.SystemMismatch(address(systemRegistry), cacheStoreRegistry);
        }
    }

    /// @inheritdoc IStatsCalculator
    /// @dev No op
    function snapshot() external override {
        // Intentionally left blank
    }

    /// @notice Returns actual calculators this calculator needs to reference
    function baseCalculators() external view returns (address[] memory calculators) {
        calculators = _baseCalculators;
    }

    /// @inheritdoc IStatsCalculator
    /// @dev Always returns false
    function shouldSnapshot() external pure override returns (bool) {
        return false;
    }
}
