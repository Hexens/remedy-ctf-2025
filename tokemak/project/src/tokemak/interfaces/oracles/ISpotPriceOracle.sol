// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/// @notice An oracle that can provide spot prices for tokens using specific liquidity pools
interface ISpotPriceOracle {
    /**
     * @notice Retrieve the spot price for a token in a specified quote currency utilizing a specific liquidity pool
     * @dev The function will attempt to retrieve the price in the requested quote currency,
     *      but might return a price in an alternative quote currency if the requested one isn't available.
     *      It's the caller's responsibility to handle the potentially different returned quote currency.
     * @param token The token to get the spot price of
     * @param pool The liquidity pool to use for the price retrieval
     * @param requestedQuoteToken The desired quote token (e.g. WETH) for the returned price
     * @return price The spot price of the token
     * @return actualQuoteToken The actual quote token used for the returned price
     */
    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) external returns (uint256 price, address actualQuoteToken);

    /**
     * @notice In memory struct for gathering all the info required for reserves for a safe spot price calculation
     *
     * @param token Pool token
     * @param reserveAmount amount of the token in the pool
     * @param rawSpotPrice Price of the token in the pool
     * @param actualQuoteToken Actual quote token used for the rawSpotPrice
     */
    struct ReserveItemInfo {
        address token;
        uint256 reserveAmount;
        uint256 rawSpotPrice;
        address actualQuoteToken;
    }

    /**
     * @notice Retrieve the total supply of the LP token for the specified pool
     *
     * @param pool The liquidity pool to use for the check
     * @param lpToken LP token of the specified pool
     * @param quoteToken The desired quote token (e.g. WETH) for the returned price
     * @return totalLPSupply Total supply of the LP token
     * @return reserves `ReserveItemInfo` struct containing the reserves info
     */
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address quoteToken
    ) external returns (uint256 totalLPSupply, ReserveItemInfo[] memory reserves);

    /**
     * @notice Retrieve the description of the oracle
     * @return description
     */
    function getDescription() external view returns (string memory);
}
