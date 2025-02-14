// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { Stats } from "src/tokemak/stats/Stats.sol";

import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IBalancerGyroPool } from "src/tokemak/interfaces/external/balancer/IBalancerGyroPool.sol";
import { BalancerStablePoolCalculatorBase } from "src/tokemak/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";
import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract BalancerGyroPoolCalculator is BalancerStablePoolCalculatorBase {
    // Gyro e-clp pools are suited for stable swaps and have 2 pool tokens
    uint256[2] public reservesEth;
    uint256 public constant DEX_RESERVE_ALPHA = 33e16; // filter coefficient of 0.33

    event UpdatedReservesEth(
        uint256 currentTimestamp, uint256 index, uint256 priorReservesEth, uint256 updatedReservesEth
    );

    constructor(
        ISystemRegistry _systemRegistry,
        address _balancerVault
    ) BalancerStablePoolCalculatorBase(_systemRegistry, _balancerVault) { }

    function calculateReserveInEthByIndex(
        IRootPriceOracle pricer,
        uint256[] memory balances,
        uint256 index,
        bool inSnapshot
    ) internal virtual override returns (uint256) {
        address token = reserveTokens[index];

        // the price oracle is always 18 decimals, so divide by the decimals of the token
        // to ensure that we always report the value in ETH as 18 decimals
        uint256 divisor = 10 ** IERC20Metadata(token).decimals();

        // slither-disable-next-line reentrancy-benign,reentrancy-no-eth
        uint256 currentReserve = pricer.getPriceInEth(token) * balances[index] / divisor;

        // Pass through filter if the filter is initialized. fee/reserve filter trigger on at the same time
        if (feeAprFilterInitialized) {
            currentReserve = Stats.getFilteredValue(DEX_RESERVE_ALPHA, reservesEth[index], currentReserve);
        }
        // Is it time to run a snapshot and update filter state?
        if (inSnapshot) {
            // slither-disable-next-line reentrancy-events
            emit UpdatedReservesEth(block.timestamp, index, reservesEth[index], currentReserve);
            reservesEth[index] = currentReserve;
        }
        return currentReserve;
    }

    function getVirtualPrice() internal view override returns (uint256 virtualPrice) {
        virtualPrice = IBalancerGyroPool(poolAddress).getInvariantDivActualSupply();
    }

    function getPoolTokens() internal view override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (tokens, balances) = BalancerUtilities._getPoolTokens(balancerVault, poolAddress);
    }
}
