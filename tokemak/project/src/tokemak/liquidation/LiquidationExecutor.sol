// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { ILiquidationRow } from "src/tokemak/interfaces/liquidation/ILiquidationRow.sol";

/**
 * @title LiquidationExecutor
 * @notice Used for off-chain component to simulate gas of a claim+liquidate+distribute
 */
contract LiquidationExecutor is Ownable {
    ILiquidationRow public immutable liquidationRow;

    constructor(
        address _liquidationRow
    ) {
        liquidationRow = ILiquidationRow(_liquidationRow);
    }

    function execute(
        IDestinationVault[] memory claimForVaults,
        ILiquidationRow.LiquidationParams[] memory liquidationParams
    ) external onlyOwner {
        liquidationRow.claimsVaultRewards(claimForVaults);
        liquidationRow.liquidateVaultsForTokens(liquidationParams);
    }
}
