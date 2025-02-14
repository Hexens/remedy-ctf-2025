// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { IStatsCalculatorFactory } from "src/tokemak/interfaces/stats/IStatsCalculatorFactory.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract StatsCalculatorRegistry is SystemComponent, IStatsCalculatorRegistry, SecurityBase {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Currently registered factory. Only thing can register new calculators
    IStatsCalculatorFactory public factory;

    /// slither-disable-start uninitialized-state
    /// @notice Calculators registered in this system by id
    mapping(bytes32 => address) public calculators;

    /// @notice Calculator addresses from calculators mapping for list iteration
    EnumerableSet.Bytes32Set private calculatorIds;
    /// slither-disable-end uninitialized-state

    modifier onlyFactory() {
        if (msg.sender != address(factory)) {
            revert OnlyFactory();
        }
        _;
    }

    event FactorySet(address newFactory);
    event StatCalculatorRegistered(bytes32 aprId, address calculatorAddress, address caller);
    event StatCalculatorRemoved(bytes32 aprId, address calculatorAddress, address caller);

    error OnlyFactory();
    error AlreadyRegistered(bytes32 aprId, address calculator);

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc IStatsCalculatorRegistry
    function getCalculator(
        bytes32 aprId
    ) external view returns (IStatsCalculator calculator) {
        address calcAddress = calculators[aprId];
        Errors.verifyNotZero(calcAddress, "calcAddress");

        calculator = IStatsCalculator(calcAddress);
    }

    /// @inheritdoc IStatsCalculatorRegistry
    function listCalculators() external view returns (bytes32[] memory ids, address[] memory addresses) {
        ids = calculatorIds.values();
        addresses = new address[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            addresses[i] = calculators[ids[i]];
        }
    }

    /// @inheritdoc IStatsCalculatorRegistry
    function register(
        address calculator
    ) external onlyFactory {
        Errors.verifyNotZero(calculator, "calculator");

        bytes32 aprId = IStatsCalculator(calculator).getAprId();
        Errors.verifyNotZero(aprId, "aprId");

        // Calculators cannot be replaced.
        // New calculators, or versions of calculators, should generate unique ids
        if (calculators[aprId] != address(0)) {
            revert AlreadyRegistered(aprId, calculator);
        }

        calculators[aprId] = calculator;
        // slither-disable-next-line unused-return
        calculatorIds.add(aprId);

        emit StatCalculatorRegistered(aprId, calculator, msg.sender);
    }

    /// @inheritdoc IStatsCalculatorRegistry
    function removeCalculator(
        bytes32 aprId
    ) external hasRole(Roles.STATS_CALC_REGISTRY_MANAGER) {
        address calcAddress = calculators[aprId];
        if (calcAddress == address(0)) {
            revert Errors.NotRegistered();
        }
        delete calculators[aprId];
        // slither-disable-next-line unused-return
        calculatorIds.remove(aprId);

        emit StatCalculatorRemoved(aprId, calcAddress, msg.sender);
    }

    /// @inheritdoc IStatsCalculatorRegistry
    function setCalculatorFactory(
        address calculatorFactory
    ) external hasRole(Roles.STATS_CALC_REGISTRY_MANAGER) {
        Errors.verifyNotZero(address(calculatorFactory), "factory");
        Errors.verifySystemsMatch(address(this), calculatorFactory);

        emit FactorySet(calculatorFactory);
        factory = IStatsCalculatorFactory(calculatorFactory);
    }
}
