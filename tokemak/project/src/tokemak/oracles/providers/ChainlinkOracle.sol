// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import {
    BaseAggregatorV3OracleInformation,
    ISystemRegistry
} from "src/tokemak/oracles/providers/base/BaseAggregatorV3OracleInformation.sol";
import { IOffchainAggregator } from "src/tokemak/interfaces/external/chainlink/IOffchainAggregator.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

/**
 * @title Gets the value of tokens that Chainlink provides a feed for.
 * @dev Many Chainlink feeds price in USD, this contract converts all pricing to Eth.
 * @dev Returns 18 decimals of precision.
 */
contract ChainlinkOracle is BaseAggregatorV3OracleInformation {
    constructor(
        ISystemRegistry _systemRegistry
    ) BaseAggregatorV3OracleInformation(_systemRegistry) { }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "chainlink";
    }

    /**
     * @notice Validates the price returned by oracle.
     * @dev This function only needs to be invoked for oracles which implement IOffchainAggregator.
     * @param oracleInfo OracleInfo of the token being validated.
     * @param roundId Round ID of the price obtained from oracle.
     * @param price Price obtained from oracle.
     */
    function _validateOffchainAggregator(OracleInfo memory oracleInfo, uint80 roundId, int256 price) internal view {
        IOffchainAggregator aggregator = IOffchainAggregator(oracleInfo.oracle.aggregator());

        if (roundId == 0 || price == (int256(aggregator.maxAnswer())) || price == (int256(aggregator.minAnswer()))) {
            revert Errors.InvalidDataReturned();
        }
    }

    /**
     * @notice Fetches the price of a token in ETH denomination.
     * @param token Address of token.
     * @return priceInEth Price of token in ETH.
     */
    function getPriceInEth(
        address token
    ) external returns (uint256 priceInEth) {
        OracleInfo memory oracleInfo = _getOracleInfo(token);
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 price,, uint256 updatedAt,) = oracleInfo.oracle.latestRoundData();
        _validateOffchainAggregator(oracleInfo, roundId, price);
        priceInEth = BaseAggregatorV3OracleInformation._getPriceInEth(token, oracleInfo, price, updatedAt);
    }
}
