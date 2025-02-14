// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";
import { IRateProvider } from "src/tokemak/interfaces/external/balancer/IRateProvider.sol";

contract OsethLSTCalculator is LSTCalculatorBase {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Price feed for osToken (e.g osETH price in ETH)
    IRateProvider public osEthPriceOracle;

    /// =====================================================
    /// Structs
    /// =====================================================

    /// @notice Initialization params specific to this calculator
    /// @param priceOracle Price feed for osToken (e.g osETH price in ETH)
    /// @param baseInitData Encoded data required by the LSTCalculatorBase initialize
    struct OsEthInitData {
        address priceOracle;
        bytes baseInitData;
    }

    /// =====================================================
    /// Events
    /// =====================================================

    event OsEthPriceOracleSet(address newOracle);

    /// =====================================================
    /// Functions - Constructor/Init
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    function initialize(bytes32[] calldata dependentCalcIds, bytes memory initData) public virtual override {
        OsEthInitData memory decodedInitData = abi.decode(initData, (OsEthInitData));

        _setOsEthPriceOracle(decodedInitData.priceOracle);

        // Base initialize has the initializer modifier so if you don't call this fn
        // be sure to protect this from double initialization
        super.initialize(dependentCalcIds, decodedInitData.baseInitData);
    }

    /// =====================================================
    /// Functions - Public
    /// =====================================================

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        return osEthPriceOracle.getRate();
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }

    /// @notice Set a new price oracle of the osETH getRate() call
    /// @dev Requires STATS_GENERAL_MANAGER role
    /// @param newOracle Address of the new oracle
    function setOsEthPriceOracle(
        address newOracle
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        _setOsEthPriceOracle(newOracle);
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    function _setOsEthPriceOracle(
        address newOracle
    ) private {
        Errors.verifyNotZero(newOracle, "priceOracle");

        osEthPriceOracle = IRateProvider(newOracle);

        emit OsEthPriceOracleSet(newOracle);
    }
}
