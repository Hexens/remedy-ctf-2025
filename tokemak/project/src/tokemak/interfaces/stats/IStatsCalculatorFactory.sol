// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";

/// @title Create and register stat calculators
interface IStatsCalculatorFactory is ISystemComponent {
    /// @notice Create an instance of a calculator pointed to a pool or destination
    /// @param aprTemplateId id of the template registered with the factory
    /// @param dependentAprIds apr ids that cover the dependencies of this calculator
    /// @param initData setup data specific to the type of calculator
    /// @return calculatorAddress the id that was generated based on the init data
    function create(
        bytes32 aprTemplateId,
        bytes32[] calldata dependentAprIds,
        bytes calldata initData
    ) external returns (address calculatorAddress);

    /// @notice Register a new template
    /// @dev Does not allow overwriting an aprTemplateId, must replace or remove first
    /// @param aprTemplateId id of the template
    /// @param newTemplate address of the template
    function registerTemplate(bytes32 aprTemplateId, address newTemplate) external;

    /// @dev Requires an existing registration. Specified old template must match. New can't match old
    /// @param aprTemplateId id of the template
    /// @param oldTemplate address of currently registered template
    /// @param newTemplate address of new template to register with id
    function replaceTemplate(bytes32 aprTemplateId, address oldTemplate, address newTemplate) external;

    /// @notice Remove a registered template
    /// @dev Must have a template set with id or will revert
    /// @param aprTemplateId id of the template
    function removeTemplate(
        bytes32 aprTemplateId
    ) external;
}
