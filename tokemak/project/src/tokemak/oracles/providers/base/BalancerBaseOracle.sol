// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Utilities } from "src/tokemak/libs/Utilities.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IBasePool } from "src/tokemak/interfaces/external/balancer/IBasePool.sol";
import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import { IAsset } from "src/tokemak/interfaces/external/balancer/IAsset.sol";
import { ISpotPriceOracle } from "src/tokemak/interfaces/oracles/ISpotPriceOracle.sol";

/// @dev This version of Bal oracles have been DEPRECATED.  See BalancerBaseStableMathOracle.sol for newest version

abstract contract BalancerBaseOracle is SystemComponent, ISpotPriceOracle {
    /// @notice The Balancer Vault that all tokens we're resolving here should reference
    /// @dev BPTs themselves are configured with an immutable vault reference
    IVault public immutable balancerVault;

    error InvalidToken(address token);
    error InvalidPool(address pool);

    constructor(ISystemRegistry _systemRegistry, IVault _balancerVault) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");
        Errors.verifyNotZero(address(_balancerVault), "_balancerVault");

        balancerVault = _balancerVault;
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address requestedQuoteToken
    ) public returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(requestedQuoteToken, "requestedQuoteToken");

        bytes32 poolId = IBasePool(pool).getPoolId();

        // Will revert with BAL#500 on invalid pool id
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);

        uint256 nTokens = tokens.length;
        if (nTokens == 0) {
            revert InvalidPool(pool);
        }

        (price, actualQuoteToken) = _getSpotPrice(token, pool, tokens, requestedQuoteToken);
    }

    function getTotalSupply_(
        address lpToken
    ) internal virtual returns (uint256 totalSupply);
    function getPoolTokens_(
        address pool
    ) internal virtual returns (IERC20[] memory tokens, uint256[] memory balances);

    ///@notice Returns the total supply of the pool and the reserves (without pool token for composable pools)
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address quoteToken
    ) external returns (uint256 totalLPSupply, ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(lpToken, "lpToken");
        Errors.verifyNotZero(quoteToken, "quoteToken");

        totalLPSupply = getTotalSupply_(pool);

        // Get the pool tokens/reserves
        (IERC20[] memory tokens, uint256[] memory balances) = getPoolTokens_(pool);

        uint256 nTokens = tokens.length;
        reserves = new ReserveItemInfo[](nTokens);

        for (uint256 i = 0; i < nTokens; ++i) {
            address token = address(tokens[i]);
            (uint256 spotPrice, address actualQuoteToken) = _getSpotPrice(token, pool, tokens, quoteToken);
            reserves[i] = ReserveItemInfo(token, balances[i], spotPrice, actualQuoteToken);
        }
    }

    function _getSpotPrice(
        address token,
        address pool,
        IERC20[] memory tokens,
        address requestedQuoteToken
    ) internal virtual returns (uint256 price, address actualQuoteToken) {
        // Scaling price down to minimize impacts on low liquidity pools.
        (uint256 downScaledUint, uint256 padUnit) = Utilities.getScaleDownFactor(IERC20Metadata(token).decimals());

        bytes32 poolId = IBasePool(pool).getPoolId();

        IVault.BatchSwapStep[] memory steps = new IVault.BatchSwapStep[](1);
        steps[0] = IVault.BatchSwapStep(poolId, 0, 1, downScaledUint, "");

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

        // Prepare swap parameters.
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokens[uint256(tokenIndex)]));
        assets[1] = IAsset(actualQuoteToken);

        IVault.FundManagement memory funds = IVault.FundManagement(address(this), false, payable(address(this)), false);

        // Perform the batch swap query to get price information.
        int256[] memory assetDeltas = balancerVault.queryBatchSwap(IVault.SwapKind.GIVEN_IN, steps, assets, funds);

        // Calculate the price based on the asset deltas and the pool fee.
        uint256 fee = IBasePool(pool).getSwapFeePercentage();

        // Add swap fee to the price calculation.
        // Balancer Fee is in 1e18.
        // Scaling price back up to get to value representitive of one full asset swapped.
        price = (uint256(-assetDeltas[1]) * (1e18 * padUnit)) / (1e18 - fee);
    }
}
