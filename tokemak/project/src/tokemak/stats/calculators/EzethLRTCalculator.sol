// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IRestakeManager } from "src/tokemak/interfaces/external/renzo/IRestakeManager.sol";
import { LSTCalculatorBase } from "src/tokemak/stats/calculators/base/LSTCalculatorBase.sol";

contract EzethLRTCalculator is LSTCalculatorBase {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Restake Manager for ezEth token. Used to get TVL in Renzo system
    IRestakeManager public renzoRestakeManger;

    /// @notice Initialization params specific to this calculator
    /// @param restakeManager Renzo restake manager contract
    /// @param baseInitData Encoded data required by the LSTCalculatorBase initialize
    struct EzEthInitData {
        address restakeManager;
        bytes baseInitData;
    }

    /// =====================================================
    /// Events
    /// =====================================================

    event RenzoRestakeManagerSet(address renzoRestakeManager);

    /// =====================================================
    /// Functions - Constructor/Init
    /// =====================================================

    constructor(
        ISystemRegistry _systemRegistry
    ) LSTCalculatorBase(_systemRegistry) { }

    function initialize(bytes32[] calldata dependentCalcIds, bytes memory initData) public virtual override {
        EzEthInitData memory decodedInitData = abi.decode(initData, (EzEthInitData));

        _setRenzoRestakeManager(decodedInitData.restakeManager);

        super.initialize(dependentCalcIds, decodedInitData.baseInitData);
    }

    /// =====================================================
    /// Functions - Public
    /// =====================================================

    /// @inheritdoc LSTCalculatorBase
    function calculateEthPerToken() public view override returns (uint256) {
        // Get the total TVL priced in ETH from restakeManager
        // slither-disable-next-line unused-return
        (,, uint256 totalTVL) = renzoRestakeManger.calculateTVLs();

        uint256 totalSupply = IERC20(lstTokenAddress).totalSupply();

        if (totalSupply == 0) {
            return 1e18;
        }

        return (10 ** 18 * totalTVL) / totalSupply;
    }

    /// @inheritdoc LSTCalculatorBase
    function usePriceAsDiscount() public pure override returns (bool) {
        return false;
    }

    /// @notice Set a new restake manager for the token
    /// @dev Requires STATS_GENERAL_MANAGER role
    /// @param newRestakeManager Address of the new restake manager
    function setRenzoRestakeManager(
        address newRestakeManager
    ) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        _setRenzoRestakeManager(newRestakeManager);
    }

    /// =====================================================
    /// Private Helpers
    /// =====================================================

    function _setRenzoRestakeManager(
        address newRestakeManager
    ) private {
        Errors.verifyNotZero(newRestakeManager, "newRestakeManager");

        renzoRestakeManger = IRestakeManager(newRestakeManager);

        emit RenzoRestakeManagerSet(newRestakeManager);
    }
}
