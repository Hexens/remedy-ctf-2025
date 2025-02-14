// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

// solhint-disable var-name-mixedcase

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISpotPriceOracle } from "src/tokemak/interfaces/oracles/ISpotPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ICurveResolver } from "src/tokemak/interfaces/utils/ICurveResolver.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Utilities } from "src/tokemak/libs/Utilities.sol";
import { ICurveV2Swap } from "src/tokemak/interfaces/external/curve/ICurveV2Swap.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract CurveV2CryptoEthOracle is SystemComponent, SecurityBase, ISpotPriceOracle {
    uint256 public constant FEE_PRECISION = 1e10;
    ICurveResolver public immutable curveResolver;
    address public immutable WETH;

    /**
     * @notice Struct for necessary information for single Curve pool.
     * @param pool The address of the curve pool.
     * @param tokenToPrice Address of the token being priced in the Curve pool.
     * @param tokenFromPrice Address of the token being used to price the token in the Curve pool.
     */
    struct PoolData {
        address pool;
        address tokenToPrice;
        address tokenFromPrice;
    }

    /**
     * @notice Emitted when token Curve pool is registered.
     * @param lpToken Lp token that has been registered.
     */
    event TokenRegistered(address lpToken);

    /**
     * @notice Emitted when a Curve pool registration is removed.
     * @param lpToken Lp token that has been unregistered.
     */
    event TokenUnregistered(address lpToken);

    /**
     * @notice Thrown when pool returned is not a v2 curve pool.
     * @param curvePool Address of the pool that was attempted to be registered.
     */
    error NotCryptoPool(address curvePool);

    /**
     * @notice Thrown when wrong lp token is returned from CurveResolver.sol.
     * @param providedLP Address of lp token provided in function call.
     * @param queriedLP Address of lp tokens returned from resolver.
     */
    error ResolverMismatch(address providedLP, address queriedLP);

    /**
     * @notice Thrown when lp token is not registered.
     * @param curveLpToken Address of token expected to be registered.
     */
    error NotRegistered(address curveLpToken);

    /**
     * @notice Thrown when a pool with an invalid number of tokens is attempted to be registered.
     * @param numTokens The number of tokens in the pool attempted to be registered.
     */
    error InvalidNumTokens(uint256 numTokens);

    /// @notice Reverse mapping of LP token to pool info.
    mapping(address => PoolData) public lpTokenToPool;

    /// @notice Mapping of pool address to it's LP token.
    mapping(address => address) public poolToLpToken;

    /**
     * @param _systemRegistry Instance of system registry for this version of the system.
     * @param _curveResolver Instance of Curve Resolver.
     */
    constructor(
        ISystemRegistry _systemRegistry,
        ICurveResolver _curveResolver
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");
        Errors.verifyNotZero(address(_curveResolver), "_curveResolver");

        curveResolver = _curveResolver;
        WETH = address(_systemRegistry.weth());
    }

    /// @inheritdoc ISpotPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "curveV2";
    }

    /**
     * @notice Allows owner of system to register a pool.
     * @dev While the reentrancy check implemented in this contact can technically be used with any token,
     *      it does not make sense to check for reentrancy unless the pool contains ETH, WETH, ERC-677, ERC-777 tokens,
     *      as the known Curve reentrancy vulnerability only works when the caller recieves these tokens.
     *      Therefore, reentrancy checks should only be set to `1` when these tokens are present.  Otherwise we
     *      waste gas claiming admin fees for Curve.
     * @dev Converts any pool tokens that are the Eth pointer address to weth. Even if pools actually hold Eth,
     *      the `coins` array returns weth address.  Still have a check for future proofing.
     * @param curvePool Address of CurveV2 pool.
     * @param curveLpToken Address of LP token associated with v2 pool.
     */
    function registerPool(address curvePool, address curveLpToken) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(curvePool, "curvePool");
        Errors.verifyNotZero(curveLpToken, "curveLpToken");
        if (lpTokenToPool[curveLpToken].pool != address(0) || poolToLpToken[curvePool] != address(0)) {
            revert Errors.AlreadyRegistered(curvePool);
        }

        (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap) =
            curveResolver.resolveWithLpToken(curvePool);

        // Only two token pools compatible with this contract.
        if (numTokens != 2) revert InvalidNumTokens(numTokens);
        if (isStableSwap) revert NotCryptoPool(curvePool);
        if (lpToken != curveLpToken) revert ResolverMismatch(curveLpToken, lpToken);

        poolToLpToken[curvePool] = curveLpToken;

        /**
         * Curve V2 pools always price second token in `coins` array in first token in `coins` array.  This means that
         *    if `coins[0]` is Weth, and `coins[1]` is rEth, the price will be rEth as base and weth as quote.
         */
        lpTokenToPool[lpToken] = PoolData({
            pool: curvePool,
            tokenToPrice: tokens[1] != LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER ? tokens[1] : WETH,
            tokenFromPrice: tokens[0] != LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER ? tokens[0] : WETH
        });

        emit TokenRegistered(lpToken);
    }

    /**
     * @notice Allows owner of system to unregister curve pool.
     * @param curveLpToken Address of CurveV2 lp token to unregister.
     */
    function unregister(
        address curveLpToken
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(curveLpToken, "curveLpToken");

        address curvePool = lpTokenToPool[curveLpToken].pool;

        if (curvePool == address(0)) revert NotRegistered(curveLpToken);

        // Remove LP token from pool mapping
        delete poolToLpToken[curvePool];
        // Remove pool from LP token mapping
        delete lpTokenToPool[curveLpToken];

        emit TokenUnregistered(curveLpToken);
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address
    ) public view returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(pool, "pool");

        address lpToken = poolToLpToken[pool];
        if (lpToken == address(0)) revert NotRegistered(pool);

        (price, actualQuoteToken) = _getSpotPrice(token, pool, lpToken);
    }

    function _getSpotPrice(
        address token,
        address pool,
        address lpToken
    ) internal view returns (uint256 price, address actualQuoteToken) {
        uint256 tokenIndex = 0;
        uint256 quoteTokenIndex = 0;

        PoolData storage poolInfo = lpTokenToPool[lpToken];

        if (token == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
            token = WETH;
        }

        // Find the token and quote token indices
        if (poolInfo.tokenToPrice == token) {
            tokenIndex = 1;
        } else if (poolInfo.tokenFromPrice == token) {
            quoteTokenIndex = 1;
        } else {
            revert NotRegistered(lpToken);
        }

        // Scale swap down token decimal to minimize swap impact on smaller pools, scale back up after swap.
        (uint256 downScaledUnit, uint256 padUnit) = Utilities.getScaleDownFactor(IERC20Metadata(token).decimals());
        uint256 dy = ICurveV2Swap(pool).get_dy(tokenIndex, quoteTokenIndex, downScaledUnit) * padUnit;

        /// @dev The fee is dynamically based on current balances; slight discrepancies post-calculation are acceptable
        /// for low-value swaps.
        uint256 fee = ICurveV2Swap(pool).fee();
        price = (dy * FEE_PRECISION) / (FEE_PRECISION - fee);

        actualQuoteToken = quoteTokenIndex == 0 ? poolInfo.tokenFromPrice : poolInfo.tokenToPrice;
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address
    ) external view returns (uint256 totalLPSupply, ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(lpToken, "lpToken");

        totalLPSupply = IERC20Metadata(lpToken).totalSupply();

        PoolData storage tokens = lpTokenToPool[lpToken];
        if (tokens.pool == address(0)) {
            revert NotRegistered(lpToken);
        }

        reserves = new ReserveItemInfo[](2); // This contract only allows CurveV2 pools with two tokens
        uint256[8] memory balances = curveResolver.getReservesInfo(pool);

        (uint256 rawSpotPrice, address actualQuoteToken) = _getSpotPrice(tokens.tokenFromPrice, pool, lpToken);
        reserves[0] = ReserveItemInfo({
            token: tokens.tokenFromPrice,
            reserveAmount: balances[0],
            rawSpotPrice: rawSpotPrice,
            actualQuoteToken: actualQuoteToken
        });

        (rawSpotPrice, actualQuoteToken) = _getSpotPrice(tokens.tokenToPrice, pool, lpToken);
        reserves[1] = ReserveItemInfo({
            token: tokens.tokenToPrice,
            reserveAmount: balances[1],
            rawSpotPrice: rawSpotPrice,
            actualQuoteToken: actualQuoteToken
        });
    }
}
