// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import {
    BaseDestinationVaultExtension,
    IDestinationVaultExtension
} from "src/tokemak/vault/extensions/base/BaseDestinationVaultExtension.sol";

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";

// solhint-disable no-inline-assembly

/// @title An extension to replace _incentiveCalculator on a destination vault
/// @dev This contract can only be accessed in a delegatecall context
contract IncentiveCalculatorUpdateDestinationVaultExtension is BaseDestinationVaultExtension {
    /// @notice Thrown when old and new calculator addresses match
    error CalculatorsMatch();

    /// @notice Emitted when an extension is updated
    event CalculatorUpdateExtensionExecuted(address newCalc, address oldCalc);

    /// @param slot Storage slot for DV._incentiveCalculator.  Find using evm.storage
    /// @param oldCalc The address of the old calculator
    /// @param newCalc The address of the new calculator
    struct IncentiveCalculatorUpdateParams {
        uint256 slot;
        address oldCalc;
        address newCalc;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseDestinationVaultExtension(_systemRegistry) { }

    /// @inheritdoc IDestinationVaultExtension
    /// @dev Use evm.storage and the address of the DV you are looking to replace the calculator for to get the slot
    function execute(
        bytes memory data
    ) external override onlyDestinationVault {
        if (!systemRegistry.accessController().hasRole(Roles.AUTO_POOL_DESTINATION_UPDATER, msg.sender)) {
            revert Errors.AccessDenied();
        }

        IncentiveCalculatorUpdateParams memory params = abi.decode(data, (IncentiveCalculatorUpdateParams));
        uint256 slot = params.slot;
        address oldCalc = params.oldCalc;
        address newCalc = params.newCalc;

        Errors.verifyNotZero(newCalc, "newCalc");
        if (oldCalc == newCalc) revert CalculatorsMatch();
        if (address(IDestinationVault(address(this)).getStats()) != oldCalc) revert Errors.InvalidConfiguration();

        address slotVal;
        // slither-disable-next-line assembly
        assembly {
            slotVal := sload(slot)

            if eq(slotVal, oldCalc) { sstore(slot, newCalc) }
        }

        if (address(IDestinationVault(address(this)).getStats()) != newCalc) revert Errors.InvalidConfiguration();

        emit CalculatorUpdateExtensionExecuted(newCalc, oldCalc);
    }
}
