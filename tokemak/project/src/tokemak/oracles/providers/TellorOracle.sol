// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { SafeCast } from "openzeppelin-contracts/utils/math/SafeCast.sol";

import {
    BaseOracleDenominations,
    ISystemRegistry,
    IPriceOracle
} from "src/tokemak/oracles/providers/base/BaseOracleDenominations.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

import { UsingTellor } from "usingtellor/UsingTellor.sol";

/**
 * @title Gets the spot price of tokens that Tellor provides a feed for.
 * @dev Will convert all tokens to Eth pricing regardless of original denomination.
 * @dev Returns 18 decimals of precision.
 */
contract TellorOracle is BaseOracleDenominations, UsingTellor {
    /// @dev Thrown when an invalid pricing timeout is submitted at oracle registration.
    error InvalidPricingTimeout(uint256 pricingTimeout);

    /// @dev Thrown when a price's timestamp is outside of freshness bounds.
    error InvalidPricingTimestamp();

    /**
     * @notice Used to store information about Tellor price queries.
     * @dev No decimals, all returned in e18 precision.
     * @param queryId bytes32 queryId for pricing query. See here: https://tellor.io/queryidstation/.
     * @param pricingTimeout Custom timeout for asset.  If 0, contract will use default defined in
     *    `BaseOracleDenominations.sol`.
     * @param denomination Enum representing denomination of price returned.
     */
    struct TellorInfo {
        bytes32 queryId;
        uint32 pricingTimeout;
        Denomination denomination;
    }

    /**
     * @notice Used to cache Tellor price and timestamp, used in case of dispute attack.
     * @param price Cached price of query.
     * @param timestamp Timestamp at which price was cached
     */
    struct TellorPriceInfo {
        uint208 price;
        uint48 timestamp;
    }

    /// @dev Minimum time to have passed since price submitted to Tellor.
    uint256 public tellorPricingFreshness = 15 minutes;

    /// @dev Token address to TellorInfo structs.
    mapping(address => TellorInfo) private tellorQueryInfo;

    /// @dev queryId => TellorPriceInfo struct.
    mapping(bytes32 => TellorPriceInfo) private tellorCachedPriceInfo;

    /// @notice Emitted when information about a Tellor query is registered.
    event TellorRegistrationAdded(address token, Denomination denomination, bytes32 _queryId);

    /// @notice Emitted when  information about a Tellor query is removed.
    event TellorRegistrationRemoved(address token, bytes32 queryId);

    /// @notice Emitted when the freshness of Tellor pricing is updated.
    event TellorPricingFreshnessUpdated(uint256 newFreshness);

    constructor(
        ISystemRegistry _systemRegistry,
        address _tellorOracleAddress
    )
        // Tellor requires payable address
        UsingTellor(payable(_tellorOracleAddress))
        BaseOracleDenominations(_systemRegistry)
    {
        Errors.verifyNotZero(_tellorOracleAddress, "tellor");
    }

    /**
     * @notice Allows ORACLE_MANAGER to set the freshness of Tellor price data
     * @param _newFreshness The new freshness time in seconds
     */
    function setTellorPricingFreshness(
        uint256 _newFreshness
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(_newFreshness, "newFreshness");
        tellorPricingFreshness = _newFreshness;
        emit TellorPricingFreshnessUpdated(_newFreshness);
    }

    /// @inheritdoc IPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "tellor";
    }

    /**
     * @notice Allows permissioned address to set _queryId, denomination for token address.
     * @param token Address of token to set queryId for.
     * @param _queryId Bytes32 queryId.
     * @param denomination Denomination of token.
     * @param pricingTimeout Custom timeout for queryId if needed.  Can be set to zero
     *      to use default defined in `BaseOracleDenominations.sol`.
     */
    function addTellorRegistration(
        address token,
        bytes32 _queryId,
        Denomination denomination,
        uint32 pricingTimeout
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "tokenForQueryId");
        Errors.verifyNotZero(_queryId, "queryId");
        if (tellorQueryInfo[token].queryId != bytes32(0)) revert Errors.MustBeZero();
        if (pricingTimeout != 0 && pricingTimeout < tellorPricingFreshness) {
            revert InvalidPricingTimeout(pricingTimeout);
        }
        tellorQueryInfo[token] =
            TellorInfo({ queryId: _queryId, denomination: denomination, pricingTimeout: pricingTimeout });
        emit TellorRegistrationAdded(token, denomination, _queryId);
    }

    /**
     * @notice Allows permissioned removal registration for token address.
     * @dev Also removes any cached pricing.
     * @param token Token to remove TellorInfo struct for.
     */
    function removeTellorRegistration(
        address token
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "tokenToRemoveRegistration");
        bytes32 queryIdBeforeDeletion = tellorQueryInfo[token].queryId;
        Errors.verifyNotZero(queryIdBeforeDeletion, "queryIdBeforeDeletion");
        delete tellorQueryInfo[token];
        delete tellorCachedPriceInfo[queryIdBeforeDeletion];
        emit TellorRegistrationRemoved(token, queryIdBeforeDeletion);
    }

    /**
     * @notice External function to view TellorInfo struct for token address.
     * @dev Will return empty struct for unregistered token address.
     * @param token Address of token to view TellorInfo struct for.
     */
    function getQueryInfo(
        address token
    ) external view returns (TellorInfo memory) {
        return tellorQueryInfo[token];
    }

    /**
     * @inheritdoc IPriceOracle
     * @dev Tellor always returns prices with 18 decimals of precision for spot pricing, so we do not need
     *      to worry about increasing or decreasing precision here.  See here:
     *      https://github.com/tellor-io/dataSpecs/blob/main/types/SpotPrice.md
     */
    // slither-disable-start timestamp
    function getPriceInEth(
        address tokenToPrice
    ) external returns (uint256) {
        TellorInfo memory tellorInfo = _getQueryInfo(tokenToPrice);
        uint256 timestamp = block.timestamp;
        uint256 tellorMaxAllowableTimestamp = timestamp - tellorPricingFreshness;

        // Giving time for Tellor network to dispute price
        (bytes memory value, uint256 timestampRetrieved) =
            getDataBefore(tellorInfo.queryId, tellorMaxAllowableTimestamp);
        uint256 tellorStoredTimeout = uint256(tellorInfo.pricingTimeout);
        uint256 tokenPricingTimeout = tellorStoredTimeout == 0 ? DEFAULT_PRICING_TIMEOUT : tellorStoredTimeout;
        uint256 price = abi.decode(value, (uint256));

        // Pre caching checks, zero checks for timestamp and price.  If these are zero, something is wrong,
        //      want to revert.
        // slither-disable-next-line incorrect-equality
        if (timestampRetrieved == 0 || price == 0) {
            revert Errors.InvalidDataReturned();
        }

        // Get Tellor cached pricing.
        TellorPriceInfo memory tellorPriceInfo = tellorCachedPriceInfo[tellorInfo.queryId];
        uint256 tellorCachedTimestamp = tellorPriceInfo.timestamp;

        // Check timestamp vs cached, replace if neccessary.
        if (timestampRetrieved > tellorCachedTimestamp) {
            tellorCachedPriceInfo[tellorInfo.queryId] =
                TellorPriceInfo({ price: SafeCast.toUint208(price), timestamp: SafeCast.toUint48(timestampRetrieved) });
        } else if (timestampRetrieved < tellorCachedTimestamp) {
            price = tellorPriceInfo.price;
            timestampRetrieved = tellorCachedTimestamp; // For checks below.
        }

        // Post caching checks, checking for timestamp validity.  Want to do this after caching checks,
        //      that way if we are using a cached value we are checking the timestamp we retrieved it at,
        //      not the timestamp we retrieved the value we queried on this call.
        if (timestampRetrieved > tellorMaxAllowableTimestamp || timestamp - timestampRetrieved > tokenPricingTimeout) {
            revert InvalidPricingTimestamp();
        }

        return _denominationPricing(tellorInfo.denomination, price, tokenToPrice);
    }
    // slither-disable-end timestamp

    /// @dev Used to enforce non-existent queryId checks
    function _getQueryInfo(
        address token
    ) private view returns (TellorInfo memory tellorInfo) {
        tellorInfo = tellorQueryInfo[token];
        Errors.verifyNotZero(tellorInfo.queryId, "queryId");
    }
}
