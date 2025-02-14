// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { IStatsCalculatorFactory } from "src/tokemak/interfaces/stats/IStatsCalculatorFactory.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";

contract StatsCalculatorFactory is SystemComponent, IStatsCalculatorFactory, SecurityBase {
    using Clones for address;

    /// @notice Registered stat calculator templates
    mapping(bytes32 => address) public templates;

    modifier onlyCreator() {
        if (!_hasRole(Roles.STATS_CALC_FACTORY_MANAGER, msg.sender)) {
            revert Errors.MissingRole(Roles.STATS_CALC_FACTORY_MANAGER, msg.sender);
        }
        _;
    }

    modifier onlyTemplateManager() {
        if (!_hasRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, msg.sender)) {
            revert Errors.MissingRole(Roles.STATS_CALC_FACTORY_TEMPLATE_MANAGER, msg.sender);
        }
        _;
    }

    event TemplateRemoved(bytes32 aprTemplateId, address template);
    event TemplateRegistered(bytes32 aprTemplateId, address newTemplate);
    event TemplateReplaced(bytes32 aprTemplateId, address oldAddress, address newAddress);

    error TemplateAlreadyRegistered(bytes32 aprTemplateId);
    error TemplateDoesNotExist(bytes32 aprTemplateId);
    error TemplateReplaceMismatch(bytes32 aprTemplateId, address actualOld, address specifiedOld);
    error TemplateReplaceMatches(bytes32 aprTemplateId, address actualOld, address specifiedOld);

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc IStatsCalculatorFactory
    function create(
        bytes32 aprTemplateId,
        bytes32[] calldata dependentAprIds,
        bytes calldata initData
    ) external onlyCreator returns (address calculatorAddress) {
        // Get the template to clone
        address template = templates[aprTemplateId];
        Errors.verifyNotZero(template, "template");

        // Copy and set it up
        calculatorAddress = template.clone();
        IStatsCalculator(calculatorAddress).initialize(dependentAprIds, initData);

        // Add the vault to the registry
        systemRegistry.statsCalculatorRegistry().register(calculatorAddress);
    }

    /// @inheritdoc IStatsCalculatorFactory
    function registerTemplate(bytes32 aprTemplateId, address newTemplate) external onlyTemplateManager {
        Errors.verifyNotZero(aprTemplateId, "aprTemplateId");
        Errors.verifyNotZero(newTemplate, "template");

        Errors.verifySystemsMatch(address(this), newTemplate);

        // Cannot overwrite an existing template
        if (templates[aprTemplateId] != address(0)) {
            revert TemplateAlreadyRegistered(aprTemplateId);
        }

        emit TemplateRegistered(aprTemplateId, newTemplate);

        templates[aprTemplateId] = newTemplate;
    }

    /// @inheritdoc IStatsCalculatorFactory
    function replaceTemplate(
        bytes32 aprTemplateId,
        address oldTemplate,
        address newTemplate
    ) external onlyTemplateManager {
        Errors.verifyNotZero(aprTemplateId, "aprTemplateId");
        Errors.verifyNotZero(oldTemplate, "oldTemplate");
        Errors.verifyNotZero(newTemplate, "newTemplate");

        // Make sure you're replacing what you think you are
        if (templates[aprTemplateId] != oldTemplate) {
            revert TemplateReplaceMismatch(aprTemplateId, templates[aprTemplateId], oldTemplate);
        }

        // If you're trying to replace with the same template you're probably
        // not doing what you think you're doing
        if (oldTemplate == newTemplate) {
            revert TemplateReplaceMatches(aprTemplateId, templates[aprTemplateId], oldTemplate);
        }

        Errors.verifySystemsMatch(address(this), newTemplate);

        emit TemplateReplaced(aprTemplateId, oldTemplate, newTemplate);

        templates[aprTemplateId] = newTemplate;
    }

    /// @inheritdoc IStatsCalculatorFactory
    function removeTemplate(
        bytes32 aprTemplateId
    ) external onlyTemplateManager {
        Errors.verifyNotZero(aprTemplateId, "aprTemplateId");

        // Template must exist otherwise why would you have called
        if (templates[aprTemplateId] == address(0)) {
            revert TemplateDoesNotExist(aprTemplateId);
        }

        emit TemplateRemoved(aprTemplateId, templates[aprTemplateId]);

        delete templates[aprTemplateId];
    }
}
