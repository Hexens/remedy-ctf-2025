// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import {
    BalancerBaseOracle,
    ISpotPriceOracle,
    Errors,
    IERC20Metadata
} from "src/tokemak/oracles/providers/base/BalancerBaseOracle.sol";
import { IBalancerGyroPool } from "src/tokemak/interfaces/external/balancer/IBalancerGyroPool.sol";

/// @title Price oracle for Gyroscope ECLP and 2CLP pools
/// @dev WARNING: Must validate that any rate providers on the pool are returning 18 decimal prices before
///  using `getPrice` function on pool.  These rate providers are assumed to be 18 decimals but there is
///  no check for this in the code.  A rate provider returning incorrect decimals can cause prices orders of
///  magnitude off
contract BalancerGyroscopeEthOracle is BalancerBaseOracle {
    /// @notice This oracle only works for two token pools
    uint256 public constant POOL_TOKENS_CONSTANT = 2;

    constructor(
        ISystemRegistry _systemRegistry,
        IVault _balancerVault
    ) BalancerBaseOracle(_systemRegistry, _balancerVault) { }

    /// @inheritdoc ISpotPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "balGyro";
    }

    /// @inheritdoc BalancerBaseOracle
    function getTotalSupply_(
        address lpToken
    ) internal virtual override returns (uint256 totalSupply) {
        totalSupply = IBalancerGyroPool(lpToken).getActualSupply();
    }

    /// @inheritdoc BalancerBaseOracle
    function getPoolTokens_(
        address pool
    ) internal virtual override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (tokens, balances) = BalancerUtilities._getPoolTokens(balancerVault, pool);
    }

    /// @inheritdoc BalancerBaseOracle
    function _getSpotPrice(
        address token,
        address pool,
        IERC20[] memory tokens,
        address
    ) internal view override returns (uint256 price, address actualQuoteToken) {
        Errors.verifyArrayLengths(tokens.length, POOL_TOKENS_CONSTANT, "tokens");

        int256 tokenIdx = -1;
        if (token == address(tokens[0])) {
            tokenIdx = 0;
        } else if (token == address(tokens[1])) {
            tokenIdx = 1;
        }

        if (tokenIdx == -1) revert InvalidToken(token);

        // Gyro pools return token0 in terms of token1
        price = IBalancerGyroPool(pool).getPrice();

        // Adjust price in case that token desired to be priced is idx 1.  Set actualQuote for return
        if (tokenIdx == 1) {
            // Price in e18
            price = 1e36 / price;
            actualQuoteToken = address(tokens[0]);
        } else {
            actualQuoteToken = address(tokens[1]);
        }

        // Gyro pools return price in e18, adjust by decimals of quote if necessary
        uint256 quoteTokenDecimals = IERC20Metadata(actualQuoteToken).decimals();
        if (quoteTokenDecimals < 18) {
            price = price / 10 ** (18 - quoteTokenDecimals);
        } else if (quoteTokenDecimals > 18) {
            price = price * 10 ** (quoteTokenDecimals - 18);
        }
    }
}
