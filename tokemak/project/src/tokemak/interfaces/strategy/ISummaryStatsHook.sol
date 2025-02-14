// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IStrategy } from "src/tokemak/interfaces/strategy/IStrategy.sol";
import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";

/// @title An interface for hooks for IStrategy.SummaryStats manipulations
interface ISummaryStatsHook {
    /**
     * @notice Used to execute hook that will modify IStrategy.SummaryStats struct
     * @param stats IStrategy.SummaryStats struct for destination stats
     * @param autoPool Address of autopool that rebalance is happening for
     * @param destAddress Address of destination
     * @param price Price per share
     * @param direction Rebalance direction, in or out
     * @param amount Amount of asset that stats are evaluated at
     * @return IStrategy.SummaryStats struct
     */
    function execute(
        IStrategy.SummaryStats memory stats,
        IAutopool autoPool,
        address destAddress,
        uint256 price,
        IAutopoolStrategy.RebalanceDirection direction,
        uint256 amount
    ) external returns (IStrategy.SummaryStats memory);
}
