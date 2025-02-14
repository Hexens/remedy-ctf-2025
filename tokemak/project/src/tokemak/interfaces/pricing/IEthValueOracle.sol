// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IEthValueOracle {
    /**
     * @notice Emitted when value provider is added.
     * @param token Address of token to be mapped with valueProvider.
     * @param valueProviderAddress Address for value provider.
     */
    event ValueProviderAdded(address token, address valueProviderAddress);

    /**
     * @notice Emitted when a value provider is removed.
     * @param token Address of token to remove value provider from.
     * @param valueProviderRemoved Address of value provider removed from token.
     */
    event ValueProviderRemoved(address token, address valueProviderRemoved);

    /**
     * @notice Revert when zero amount.
     */
    error CannotBeZeroAmount();

    /**
     * @notice Allows privileged address to add value providers.
     * @dev Privileged access function.
     * @param token Address of token.
     * @param valueProvider Address of value provider.
     */
    function addValueProvider(address token, address valueProvider) external;

    /**
     * @notice Used to remove value provider from token => value provider mapping.
     * @dev Resets to address(0);
     * @param token Token to remove value provider from.
     */
    function removeValueProvider(
        address token
    ) external;

    /**
     * @notice Returns the price for an amount of token.
     * @dev This function assumes that input values are in the precision of the input token, ie usdc is input
     *      with 6 decimals of precision, the amount returned by its `decimals()` function.  Failure to adhere
     *      to this will result in values that are off by orders of magnitude.
     * @dev priceForValueProvider should always be false for external calls, true for calls from value provider
     *      contracts.
     * @dev Denominations (USD, EUR, etc) aside from Eth should not be priced through this function, as they have
     *      placeholder addresses and do not adhere to ERC20 standards.
     * @param tokenToPrice Address of token to get price of.
     * @param amount Amount of token that is being priced.
     * @param priceForValueProvider Whether or not value provider is the caller.  Determines whether price
     *      returned is in 18 decimals of precision or precision input via `amount` parameter.  Precision
     *      input via `getPrice()` call needed for value provider calls to `EthValueOracle`.
     * @return price Price in eth of amount of tokenToPrice.  Precision varies on return value dependent on
     *      `priceForValueProvider` boolean.
     */
    function getPrice(
        address tokenToPrice,
        uint256 amount,
        bool priceForValueProvider
    ) external view returns (uint256 price);
}
