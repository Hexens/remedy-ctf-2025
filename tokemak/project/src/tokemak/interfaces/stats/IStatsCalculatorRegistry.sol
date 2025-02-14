// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";

/// @notice Track stat calculators for this instance of the system
interface IStatsCalculatorRegistry {
    /// @notice Get a registered calculator
    /// @dev Should revert if missing
    /// @param aprId key of the calculator to get
    /// @return calculator instance of the calculator
    function getCalculator(
        bytes32 aprId
    ) external view returns (IStatsCalculator calculator);

    /// @notice List all calculator addresses registered
    function listCalculators() external view returns (bytes32[] memory, address[] memory);

    /// @notice Register a new stats calculator
    /// @param calculator address of the calculator
    function register(
        address calculator
    ) external;

    /// @notice Remove a stats calculator
    /// @param aprId key of the calculator to remove
    function removeCalculator(
        bytes32 aprId
    ) external;

    /// @notice Set the factory that can register calculators
    /// @param factory address of the factory
    function setCalculatorFactory(
        address factory
    ) external;
}
