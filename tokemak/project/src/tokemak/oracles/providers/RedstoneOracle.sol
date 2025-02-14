// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import {
    BaseAggregatorV3OracleInformation,
    ISystemRegistry
} from "src/tokemak/oracles/providers/base/BaseAggregatorV3OracleInformation.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";

/**
 * @title Gets the value of tokens that Redstone provides a feed for.
 * @dev Many Redstone feeds price in USD, this contract converts all pricing to Eth.
 * @dev Returns 18 decimals of precision.
 */
contract RedstoneOracle is BaseAggregatorV3OracleInformation {
    constructor(
        ISystemRegistry _systemRegistry
    ) BaseAggregatorV3OracleInformation(_systemRegistry) { }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "redstone";
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(
        address token
    ) external returns (uint256 priceInEth) {
        OracleInfo memory oracleInfo = BaseAggregatorV3OracleInformation._getOracleInfo(token);
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 updatedAt,) = oracleInfo.oracle.latestRoundData();
        priceInEth = BaseAggregatorV3OracleInformation._getPriceInEth(token, oracleInfo, price, updatedAt);
    }
}
