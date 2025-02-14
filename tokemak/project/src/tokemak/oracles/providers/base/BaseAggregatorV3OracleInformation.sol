// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { BaseOracleDenominations, ISystemRegistry } from "src/tokemak/oracles/providers/base/BaseOracleDenominations.sol";
import { IAggregatorV3Interface } from "src/tokemak/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

abstract contract BaseAggregatorV3OracleInformation is BaseOracleDenominations {
    /**
     * @notice Used to store info on token's oracle feed.
     * @param oracle Address of oracle for token mapped.
     * @param pricingTimeout Custom timeout for asset pricing.  If 0, contract will use
     *      default defined in `BaseOracleDenominations.sol`.
     * @param denomination Enum representing what token mapped is denominated in.
     * @param decimals Number of decimal precision that oracle returns.  Can differ from
     *      token decimals in some cases.
     */
    struct OracleInfo {
        IAggregatorV3Interface oracle;
        uint32 pricingTimeout;
        Denomination denomination;
        uint8 decimals;
    }

    /// @dev Mapping of token to OracleInfo struct.  Private to enforce zero address checks.
    mapping(address => OracleInfo) private tokenToOracle;

    /**
     * @notice Emitted when a token has an oracle address set.
     * @param token Address of token.
     * @param oracle Address of oracle contract.
     * @param denomination Enum representing denomination.
     * @param decimals Number of decimals precision that oracle returns.
     */
    event OracleRegistrationAdded(address token, address oracle, Denomination denomination, uint8 decimals);

    /**
     * @notice Emitted when token to oracle mapping deleted.
     * @param token Address of token.
     * @param oracle Address of oracle.
     */
    event OracleRegistrationRemoved(address token, address oracle);

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseOracleDenominations(_systemRegistry) { }

    /**
     * @notice Allows oracle address and denominations to be set for token.
     * @param token Address of token for which oracle will be set.
     * @param oracle Address of oracle to be set.
     * @param denomination Address of denomination to be set.
     * @param pricingTimeout Custom timeout for price feed if desired.  Can be set to
     *      zero to use default defined in `BaseOracleDenominations.sol`.
     */
    function registerOracle(
        address token,
        IAggregatorV3Interface oracle,
        Denomination denomination,
        uint32 pricingTimeout
    ) public hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "tokenToAddOracle");
        Errors.verifyNotZero(address(oracle), "oracle");
        if (address(tokenToOracle[token].oracle) != address(0)) revert Errors.AlreadyRegistered(token);

        uint8 oracleDecimals = oracle.decimals();
        tokenToOracle[token] = OracleInfo({
            oracle: oracle,
            denomination: denomination,
            decimals: oracleDecimals,
            pricingTimeout: pricingTimeout
        });

        emit OracleRegistrationAdded(token, address(oracle), denomination, oracleDecimals);
    }

    /**
     * @notice Allows oracle address and denominations to be removed.
     * @param token Address of token to remove registration for.
     * @return oracleBeforeDeletion Address of oracle for 'token' before deletion.
     */
    function removeOracleRegistration(
        address token
    ) public hasRole(Roles.ORACLE_MANAGER) returns (address oracleBeforeDeletion) {
        Errors.verifyNotZero(token, "tokenToRemoveOracle");
        oracleBeforeDeletion = address(tokenToOracle[token].oracle);
        if (oracleBeforeDeletion == address(0)) revert Errors.MustBeSet();
        delete tokenToOracle[token];

        emit OracleRegistrationRemoved(token, oracleBeforeDeletion);
    }

    /**
     * @notice Returns `OracleInfo` struct with information on `address token`.
     * @dev Will return empty structs for tokens that are not registered.
     * @param token Address of token to get info for.
     * @return OracleInfo struct with information on `address token`.
     */
    function getOracleInfo(
        address token
    ) external view returns (OracleInfo memory) {
        return tokenToOracle[token];
    }

    // slither-disable-start timestamp
    function _getPriceInEth(
        address token,
        OracleInfo memory oracleInfo,
        int256 price,
        uint256 updatedAt
    ) internal returns (uint256) {
        uint256 timestamp = block.timestamp;
        uint256 oracleStoredTimeout = uint256(oracleInfo.pricingTimeout);
        uint256 tokenPricingTimeout = oracleStoredTimeout == 0 ? DEFAULT_PRICING_TIMEOUT : oracleStoredTimeout;

        if (price <= 0) revert Errors.InvalidDataReturned(); // Check before conversion from int to uint.
        uint256 priceUint = uint256(price);

        if (updatedAt == 0 || updatedAt > timestamp || updatedAt < timestamp - tokenPricingTimeout) {
            revert Errors.InvalidDataReturned();
        }
        uint256 decimals = oracleInfo.decimals;
        // Oracle feeds have certain decimal precisions, does not necessarily conform to underlying asset.
        uint256 scaledPrice = decimals <= 18 ? priceUint * 10 ** (18 - decimals) : priceUint / 10 ** (decimals - 18);

        return _denominationPricing(oracleInfo.denomination, scaledPrice, token);
    }
    // slither-disable-end timestamp

    /// @dev internal getter to access `tokenToOracle` mapping, enforces address(0) check.
    function _getOracleInfo(
        address token
    ) internal view returns (OracleInfo memory oracleInfo) {
        oracleInfo = tokenToOracle[token];
        Errors.verifyNotZero(address(oracleInfo.oracle), "Oracle");
    }
}
