// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPufferVault } from "src/tokemak/interfaces/external/puffer/IPufferVault.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";

contract PufEthLRTCalculator is LSTCalculatorBase {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Puffer Vault representing the pufEth token. Used to get TVL in Puffer protocol
    IPufferVault public pufferVault;

    /// @param pufferVault Puffer vault contract
    /// @param baseInitData Encoded data required by the LSTCalculatorBase initialize
    struct PufEthInitData {
        address pufferVault;
        bytes baseInitData;
    }

    /// =====================================================
    /// Events
    /// =====================================================

    event PufEthVaultSet(address pufferVault);

    /// =====================================================
    /// Functions - Constructor/Init
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    function initialize(bytes32[] calldata dependentCalcIds, bytes memory initData) public virtual override {
        PufEthInitData memory decodedInitData = abi.decode(initData, (PufEthInitData));

        _setPufEthVault(decodedInitData.pufferVault);

        super.initialize(dependentCalcIds, decodedInitData.baseInitData);
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Sets the new PufEthVault
    /// @dev Requires STATS_GENERAL_MANAGER role
    /// @param newPufferVault Address of the new Puffer Vault
    function setPufEthVault(
        address newPufferVault
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        _setPufEthVault(newPufferVault);
    }

    /// =====================================================
    /// Functions - Public
    /// =====================================================

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        // We convert 1 ETH to equivalent of 1 PufEth using the PufferVault conversion function from ERC4626
        return pufferVault.convertToAssets(1e18);
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    function _setPufEthVault(
        address _pufferVault
    ) private {
        Errors.verifyNotZero(_pufferVault, "_pufferVault");

        pufferVault = IPufferVault(_pufferVault);

        emit PufEthVaultSet(_pufferVault);
    }
}
