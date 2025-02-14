// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20Metadata, IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ISpotPriceOracle } from "src/tokemak/interfaces/oracles/ISpotPriceOracle.sol";
import { IBalancerStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerStablePool.sol";

import { StableMath } from "src/tokemak/external/balancer/StableMath.sol";
import { ScalingHelpers } from "src/tokemak/external/balancer/ScalingHelpers.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

import { SystemComponent, ISystemRegistry } from "src/tokemak/SystemComponent.sol";

/// @title A base contract for Balancer StableMath oracle functionalities
abstract contract BalancerBaseStableMathOracle is ISpotPriceOracle, SystemComponent {
    error InvalidToken(address token);
    error InvalidPool(address pool);

    constructor(
        ISystemRegistry _registry
    ) SystemComponent(_registry) {
        Errors.verifyNotZero(address(_registry.rootPriceOracle()), "_registry.rootPriceOracle");
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) external virtual override returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(requestedQuoteToken, "requestedQuoteToken");

        (IERC20[] memory tokens,, bytes memory data) = _getPoolTokens(pool);

        if (tokens.length == 0) {
            revert InvalidPool(pool);
        }

        (price, actualQuoteToken) = _getSpotPrice(token, pool, requestedQuoteToken, tokens, data);
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address quoteToken
    ) external virtual override returns (uint256 totalLpSupply, ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(quoteToken, "quoteToken");

        // Pool and LP token always the same for Bal
        if (lpToken != pool) revert InvalidPool(pool);

        totalLpSupply = _getTotalSupply(pool);

        // Get the pool tokens/reserves
        (IERC20[] memory tokens, uint256[] memory balances, bytes memory data) = _getPoolTokens(pool);

        uint256 nTokens = tokens.length;
        reserves = new ReserveItemInfo[](nTokens);

        for (uint256 i = 0; i < nTokens; ++i) {
            address token = address(tokens[i]);
            (uint256 spotPrice, address actualQuoteToken) = _getSpotPrice(token, pool, quoteToken, tokens, data);
            reserves[i] = ReserveItemInfo(token, balances[i], spotPrice, actualQuoteToken);
        }
    }

    /// @param token The token to get the price of
    /// @param pool The pool to use to get the price of the token
    /// @param requestedQuoteToken Desired quote token.  Will pick another token if this one is not available
    /// @param tokens Array of IERC20 instances of all tokens in pool
    /// @param extraData Data retrieved farther up the call that will be used to determine spot prices.  Varies by pool
    function _getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken,
        IERC20[] memory tokens,
        bytes memory extraData
    ) internal virtual returns (uint256 price, address actualQuoteToken) {
        int256 tokenIndex = -1;
        int256 quoteTokenIndex = -1;
        int256 alternativeQuoteTokenIndex = -1;

        // Find the token and quote token indices
        for (uint256 i = 0; i < tokens.length; ++i) {
            address t = address(tokens[i]);

            if (t == token) {
                tokenIndex = int256(i);
            } else if (t == requestedQuoteToken) {
                quoteTokenIndex = int256(i);
            } else if (pool != t) {
                // Pools may include their address as a token, which should not be chosen as quote token.
                alternativeQuoteTokenIndex = int256(i);
            }

            // Break out of the loop if both indices are found.
            if (tokenIndex != -1 && quoteTokenIndex != -1) {
                break;
            }
        }

        if (tokenIndex == -1) revert InvalidToken(token);

        // Use an the alternative quote token if the requested one is not found in the pool.
        if (quoteTokenIndex == -1) {
            quoteTokenIndex = alternativeQuoteTokenIndex;
        }

        // Set the actual quote token based on the found index.
        actualQuoteToken = address(tokens[uint256(quoteTokenIndex)]);

        // Get live balances and scaling.  StableMath done with scaled balances
        (uint256[] memory adjustedBalances, uint256[] memory scalingFactors) =
            _getLiveBalancesAndScalingFactors(extraData);
        uint256 poolAmplification = _getAmplificationParam(pool);
        uint256 currentInvariant = StableMath.computeInvariant(poolAmplification, adjustedBalances);

        // Bal swap amounts are adjusted by rate and decimal scaling
        uint256 scaledSwapAmount = ScalingHelpers.toScaled18RoundDown(
            10 ** IERC20Metadata(token).decimals(), scalingFactors[uint256(tokenIndex)]
        );

        // Returns price still scaled by rate and decimal
        uint256 unscaledPrice = StableMath.computeOutGivenExactIn(
            poolAmplification,
            adjustedBalances,
            uint256(tokenIndex),
            uint256(quoteTokenIndex),
            scaledSwapAmount,
            currentInvariant
        );

        // Spot price should be raw price, so downscale here
        price = _downscalePrice(unscaledPrice, scalingFactors[uint256(quoteTokenIndex)]);
    }

    /// @notice Gets the current amplification coefficient for a Balancer pool
    /// @param pool Address of the pool
    /// @return amplification Uint256 amplification param
    function _getAmplificationParam(
        address pool
    ) internal view virtual returns (uint256 amplification) {
        // slither-disable-next-line unused-return
        (amplification,,) = IBalancerStablePool(pool).getAmplificationParameter();
    }

    /// @notice Scaled a price down by rate and decimals scaling factor
    /// @param scaledPrice Price that is currently scaled up by rate and decimals
    /// @param scalingFactor Factor to scale price down by
    /// @return Raw value, in this context a price without rate and decimal scaling applied
    function _downscalePrice(uint256 scaledPrice, uint256 scalingFactor) internal pure virtual returns (uint256) {
        // Scaling factor here is combined for decimal and rate
        return ScalingHelpers.toRawRoundDown(scaledPrice, scalingFactor);
    }

    /// @notice Returns live balances and scaling factors for pool tokens
    /// @param data Any data this function needs to operate.  Returned from _getPoolTokens call
    /// @return liveBalances Balances scaled to 18 decimals and by rate if applicable
    /// @return scalingFactors Factors that balances are scaled by, includes decimal and rate scale
    function _getLiveBalancesAndScalingFactors(
        bytes memory data
    ) internal view virtual returns (uint256[] memory liveBalances, uint256[] memory scalingFactors);

    /// @notice Gets total supply for a pool
    /// @param pool Address of a pool
    /// @return totalSupply Total supply of a pools lp token
    function _getTotalSupply(
        address pool
    ) internal view virtual returns (uint256 totalSupply);

    /// @notice Gets information about tokens in a pool
    /// @dev Returns encoded data that may be needed in later operations
    /// @param pool Address of pool to get information on
    /// @return poolTokens Token in pool
    /// @return balances Balances of tokens in pool
    /// @return data Any data that may be need in _getLiveBalancesAndScalingFactors
    function _getPoolTokens(
        address pool
    ) internal view virtual returns (IERC20[] memory poolTokens, uint256[] memory balances, bytes memory data);
}
