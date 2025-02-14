// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/// @notice Retrieve a price for any token used in the system
interface IRootPriceOracle {
    /// @notice Returns a fair price for the provided token in ETH
    /// @param token token to get the price of
    /// @return price the price of the token in ETH
    function getPriceInEth(
        address token
    ) external returns (uint256 price);

    /// @notice Returns a spot price for the provided token in ETH, utilizing specified liquidity pool
    /// @param token token to get the spot price of
    /// @param pool liquidity pool to be used for price determination
    /// @return price the spot price of the token in ETH based on the provided pool
    function getSpotPriceInEth(address token, address pool) external returns (uint256);

    /// @notice Returns a price for base token in quote token.
    /// @dev Requires both tokens to be registered.
    /// @param base Address of base token.
    /// @param quote Address of quote token.
    /// @return price Price of the base token in quote token.
    function getPriceInQuote(address base, address quote) external returns (uint256 price);

    /// @notice Retrieve the price of LP token based on the reserves
    /// @param lpToken LP token to get the price of
    /// @param pool liquidity pool to be used for price determination
    /// @param quoteToken token to quote the price in
    function getRangePricesLP(
        address lpToken,
        address pool,
        address quoteToken
    ) external returns (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe);

    /// @notice Returns floor or ceiling price of the supplied lp token in terms of requested quote.
    /// @dev  Floor price: the minimum price among all the spot prices and safe prices of the tokens in the pool.
    ///       Ceiling price: the maximum price among all the spot prices and safe prices of the tokens in the pool.
    /// @param pool Address of pool to get spot pricing from.
    /// @param lpToken Address of the lp token to price.
    /// @param inQuote Address of desired quote token.
    /// @param ceiling Bool indicating whether to get floor or ceiling price.
    /// @return floorOrCeilingPerLpToken Floor or ceiling price of the lp token.
    function getFloorCeilingPrice(
        address pool,
        address lpToken,
        address inQuote,
        bool ceiling
    ) external returns (uint256 floorOrCeilingPerLpToken);

    function getFloorPrice(address, address, address) external returns (uint256 price);

    function getCeilingPrice(address, address, address) external returns (uint256 price);
}
