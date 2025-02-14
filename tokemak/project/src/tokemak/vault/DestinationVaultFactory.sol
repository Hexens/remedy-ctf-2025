// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { DestinationVaultMainRewarder } from "src/tokemak/rewarders/DestinationVaultMainRewarder.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { IDestinationVaultFactory } from "src/tokemak/interfaces/vault/IDestinationVaultFactory.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DestinationVaultFactory is SystemComponent, IDestinationVaultFactory, SecurityBase {
    using Clones for address;

    uint256 public defaultRewardRatio;
    uint256 public defaultRewardBlockDuration;

    modifier onlyVaultCreator() {
        if (!_hasRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, msg.sender)) {
            revert Errors.MissingRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER, msg.sender);
        }
        _;
    }

    event DefaultRewardRatioSet(uint256 rewardRatio);
    event DefaultBlockDurationSet(uint256 blockDuration);

    constructor(
        ISystemRegistry _systemRegistry,
        uint256 _defaultRewardRatio,
        uint256 _defaultRewardBlockDuration
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        // Validate the registry is in a state we can use it
        if (address(_systemRegistry.destinationTemplateRegistry()) == address(0)) {
            revert Errors.RegistryItemMissing("destinationTemplateRegistry");
        }
        if (address(_systemRegistry.destinationVaultRegistry()) == address(0)) {
            revert Errors.RegistryItemMissing("destinationVaultRegistry");
        }

        // Zero is valid here
        _setDefaultRewardRatio(_defaultRewardRatio);
        _setDefaultRewardBlockDuration(_defaultRewardBlockDuration);
    }

    /// @inheritdoc IDestinationVaultFactory
    function setDefaultRewardRatio(
        uint256 rewardRatio
    ) public hasRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER) {
        _setDefaultRewardRatio(rewardRatio);
    }

    /// @inheritdoc IDestinationVaultFactory
    function setDefaultRewardBlockDuration(
        uint256 blockDuration
    ) public hasRole(Roles.DESTINATION_VAULT_FACTORY_MANAGER) {
        _setDefaultRewardBlockDuration(blockDuration);
    }

    /// @inheritdoc IDestinationVaultFactory
    function create(
        string memory vaultType,
        address baseAsset,
        address underlyer,
        address incentiveCalculator,
        address[] memory additionalTrackedTokens,
        bytes32 salt,
        bytes memory params
    ) external onlyVaultCreator returns (address vault) {
        // Switch to the internal key from the human readable
        bytes32 key = keccak256(abi.encode(vaultType));

        // Get the template to clone
        address template = address(systemRegistry.destinationTemplateRegistry().getAdapter(key));

        Errors.verifyNotZero(template, "template");

        address newVaultAddress = template.predictDeterministicAddress(salt);

        DestinationVaultMainRewarder mainRewarder = new DestinationVaultMainRewarder{ salt: salt }(
            systemRegistry,
            newVaultAddress,
            baseAsset, // Main rewards for a dv are always in base asset
            defaultRewardRatio,
            defaultRewardBlockDuration,
            false // allowExtraRewards
        );

        // Copy and set it up
        vault = template.cloneDeterministic(salt);

        IDestinationVault(vault).initialize(
            IERC20(baseAsset), IERC20(underlyer), mainRewarder, incentiveCalculator, additionalTrackedTokens, params
        );

        // Add the vault to the registry
        systemRegistry.destinationVaultRegistry().register(vault);
    }

    function _setDefaultRewardRatio(
        uint256 rewardRatio
    ) private {
        defaultRewardRatio = rewardRatio;

        emit DefaultRewardRatioSet(rewardRatio);
    }

    function _setDefaultRewardBlockDuration(
        uint256 blockDuration
    ) private {
        defaultRewardBlockDuration = blockDuration;

        emit DefaultBlockDurationSet(blockDuration);
    }
}
