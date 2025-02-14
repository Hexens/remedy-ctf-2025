// SPDX-License-Identifier:UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { ISpotPriceOracle } from "src/tokemak/interfaces/oracles/ISpotPriceOracle.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract RootPriceOracle is SystemComponent, SecurityBase, IRootPriceOracle {
    address private immutable _weth;

    mapping(address => IPriceOracle) public tokenMappings;
    mapping(address => ISpotPriceOracle) public poolMappings;
    mapping(address => uint256) public safeSpotPriceThresholds;
    uint256 internal constant THRESHOLD_PRECISION = 10_000;

    event TokenRemoved(address token);
    event TokenRegistered(address token, address oracle);
    event TokenRegistrationReplaced(address token, address oldOracle, address newOracle);

    event SafeSpotPriceThresholdUpdated(address token, uint256 threshold);

    // pool-handler specific events
    event PoolRegistered(address indexed pool, address indexed oracle);
    event PoolRegistrationReplaced(address indexed pool, address indexed oldOracle, address indexed newOracle);
    event PoolRemoved(address indexed pool);

    error AlreadyRegistered(address token);
    error MissingTokenOracle(address token);
    error MissingSpotPriceOracle(address token);
    error MappingDoesNotExist(address token);
    error ReplaceOldMismatch(address token, address oldExpected, address oldActual);
    error ReplaceAlreadyMatches(address token, address newOracle);
    error NoThresholdFound(address token);

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        _weth = address(_systemRegistry.weth());
    }

    /// @notice Register a new token to oracle mapping
    /// @dev May require additional registration in the oracle itself
    /// @param token address of the token to register
    /// @param oracle address of the oracle to use to lookup price
    function registerMapping(address token, IPriceOracle oracle) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(address(oracle), "oracle");
        Errors.verifySystemsMatch(address(this), address(oracle));

        // We want the operation of replacing a mapping to be an explicit
        // call so we don't accidentally overwrite something
        if (address(tokenMappings[token]) != address(0)) {
            revert AlreadyRegistered(token);
        }

        tokenMappings[token] = oracle;

        emit TokenRegistered(token, address(oracle));
    }

    /// @notice Replace an existing token -> oracle mapping
    /// @dev Must exist, matching existing, and new != old value to successfully replace
    /// @param token address of the token to register
    /// @param oldOracle existing oracle address
    /// @param newOracle new oracle address
    function replaceMapping(
        address token,
        IPriceOracle oldOracle,
        IPriceOracle newOracle
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(address(oldOracle), "oldOracle");
        Errors.verifyNotZero(address(newOracle), "newOracle");
        Errors.verifySystemsMatch(address(this), address(newOracle));

        // We want to ensure you know what you're replacing so ensure
        // you provide a matching old value
        if (tokenMappings[token] != oldOracle) {
            revert ReplaceOldMismatch(token, address(oldOracle), address(tokenMappings[token]));
        }

        // If the old and new values match we can assume you're not doing
        // what you think you're doing so we just fail
        if (oldOracle == newOracle) {
            revert ReplaceAlreadyMatches(token, address(newOracle));
        }

        tokenMappings[token] = newOracle;

        emit TokenRegistrationReplaced(token, address(oldOracle), address(newOracle));
    }

    /// @notice Remove a token to oracle mapping
    /// @dev Must exist. Does not remove any additional configuration from the oracle itself
    /// @param token address of the token that is registered
    function removeMapping(
        address token
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "token");

        // If you're trying to remove something that doesn't exist then
        // some condition you're expecting isn't true. We revert so you can reevaluate
        if (address(tokenMappings[token]) == address(0)) {
            revert MappingDoesNotExist(token);
        }

        delete tokenMappings[token];

        emit TokenRemoved(token);
    }

    /// @notice Register a new liquidity pool to its LP oracle
    /// @dev May require additional registration in the oracle itself
    /// @param pool address of the liquidity pool
    /// @param oracle address of the LP oracle
    function registerPoolMapping(address pool, ISpotPriceOracle oracle) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(address(oracle), "oracle");
        Errors.verifySystemsMatch(address(this), address(oracle));

        if (address(poolMappings[pool]) != address(0)) {
            revert AlreadyRegistered(pool);
        }

        poolMappings[pool] = oracle;

        emit PoolRegistered(pool, address(oracle));
    }

    /// @notice Replace an existing oracle for a specified liquidity pool
    /// @dev Must exist, matching existing, and new != old value to successfully replace
    /// @param pool address of the liquidity pool
    /// @param oldOracle address of the current LP oracle
    /// @param newOracle address of the new LP oracle
    function replacePoolMapping(
        address pool,
        ISpotPriceOracle oldOracle,
        ISpotPriceOracle newOracle
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(address(oldOracle), "oldOracle");
        Errors.verifyNotZero(address(newOracle), "newOracle");
        Errors.verifySystemsMatch(address(this), address(newOracle));

        ISpotPriceOracle currentOracle = poolMappings[pool];

        if (currentOracle != oldOracle) revert ReplaceOldMismatch(pool, address(oldOracle), address(currentOracle));
        if (oldOracle == newOracle) revert ReplaceAlreadyMatches(pool, address(newOracle));

        poolMappings[pool] = newOracle;

        emit PoolRegistrationReplaced(pool, address(oldOracle), address(newOracle));
    }

    /// @notice Remove an existing oracle for a specified liquidity pool
    /// @dev Must exist. Does not remove any additional configuration from the oracle itself
    /// @param pool address of the liquidity pool that needs oracle removal
    function removePoolMapping(
        address pool
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(pool, "pool");

        if (address(poolMappings[pool]) == address(0)) revert MappingDoesNotExist(pool);

        delete poolMappings[pool];

        emit PoolRemoved(pool);
    }

    /// @notice Set a threshold for a token spot price discrepancy to be considered safe
    /// @param token address of the token to set the threshold for
    /// @param threshold threshold to set (precision to 2 decimal places, i.e. 10000 = 100.00%)
    function setSafeSpotPriceThreshold(address token, uint256 threshold) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(threshold, "threshold");

        if (threshold > THRESHOLD_PRECISION) revert Errors.InvalidParam("threshold");

        safeSpotPriceThresholds[token] = threshold;

        emit SafeSpotPriceThresholdUpdated(token, threshold);
    }

    /// @dev This and all price oracles are not view fn's so that we can perform the Curve reentrancy check
    /// @inheritdoc IRootPriceOracle
    function getPriceInEth(
        address token
    ) external returns (uint256 price) {
        // Skip the token address(0) check and just rely on the oracle lookup
        // Emit token so we can figure out what was actually 0 later
        IPriceOracle oracle = _checkTokenOracleRegistration(token);

        price = oracle.getPriceInEth(token);
    }

    /// @inheritdoc IRootPriceOracle
    function getFloorCeilingPrice(
        address pool,
        address lpToken,
        address inQuote,
        bool ceiling
    ) public returns (uint256 floorOrCeilingPerLpToken) {
        (uint256 totalReserves, uint256 floorOrCeilingPrice, uint256 totalLpSupply) =
            _calculateReservesAndPrice(pool, lpToken, inQuote, ceiling);
        floorOrCeilingPerLpToken = totalReserves * floorOrCeilingPrice / totalLpSupply;
    }

    /**
     * @notice Calculates the total reserves, floor/ceiling price, and total LP supply for a given pool and token pair.
     * @param pool The address of the liquidity pool.
     * @param lpToken The address of the LP token.
     * @param inQuote The address of the desired quote token.
     * @param ceiling A boolean indicating whether to calculate the ceiling price (true) or floor price (false).
     * @return totalReserves The total reserves in the pool, scaled to the desired quote token decimals.
     * @return floorOrCeilingPrice The floor or ceiling price, depending on the `ceiling` parameter.
     * @return totalLpSupply The total LP supply, scaled to the desired quote token decimals.
     */
    function _calculateReservesAndPrice(
        address pool,
        address lpToken,
        address inQuote,
        bool ceiling
    ) internal returns (uint256 totalReserves, uint256 floorOrCeilingPrice, uint256 totalLpSupply) {
        ISpotPriceOracle.ReserveItemInfo[] memory reserveInfoArray;

        ISpotPriceOracle oracle = _checkSpotOracleRegistration(pool);
        (totalLpSupply, reserveInfoArray) = oracle.getSafeSpotPriceInfo(pool, lpToken, inQuote);

        uint256 inQuoteDecimals = IERC20Metadata(inQuote).decimals();
        uint256 lpTokenDecimals = IERC20Metadata(lpToken).decimals();

        totalLpSupply = _scaleValue(totalLpSupply, lpTokenDecimals, inQuoteDecimals);

        uint256 nTokens = reserveInfoArray.length;

        for (uint256 i = 0; i < nTokens; ++i) {
            ISpotPriceOracle.ReserveItemInfo memory reserveInfo = reserveInfoArray[i];

            uint256 safePrice = getPriceInQuote(reserveInfo.token, inQuote);
            uint256 spotPrice = _enforceQuoteToken(inQuote, reserveInfo.actualQuoteToken, reserveInfo.rawSpotPrice);

            uint256 tokenPricedDecimals = IERC20Metadata(reserveInfo.token).decimals();
            // Scaling reserves, reserves are always returned in the decimals of the token priced.
            totalReserves += _scaleValue(reserveInfo.reserveAmount, tokenPricedDecimals, inQuoteDecimals);

            if (ceiling) {
                floorOrCeilingPrice = Math.max(floorOrCeilingPrice, Math.max(spotPrice, safePrice));
            } else {
                floorOrCeilingPrice = i == 0
                    ? Math.min(spotPrice, safePrice)
                    : Math.min(floorOrCeilingPrice, Math.min(spotPrice, safePrice));
            }
        }
    }

    /**
     * @dev Scales a value based on the token decimals and desired quote token decimals.
     * @param value The value to be scaled.
     * @param tokenDecimals The decimals of the token.
     * @param inQuoteDecimals The decimals of the desired quote token.
     * @return The scaled value.
     */
    function _scaleValue(
        uint256 value,
        uint256 tokenDecimals,
        uint256 inQuoteDecimals
    ) internal pure returns (uint256) {
        if (tokenDecimals > inQuoteDecimals) {
            return value / 10 ** (tokenDecimals - inQuoteDecimals);
        } else if (tokenDecimals < inQuoteDecimals) {
            return value * 10 ** (inQuoteDecimals - tokenDecimals);
        }
        return value;
    }

    /// @inheritdoc IRootPriceOracle
    function getSpotPriceInEth(address token, address pool) external returns (uint256 price) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(pool, "pool");

        ISpotPriceOracle oracle = _checkSpotOracleRegistration(pool);

        address weth = address(systemRegistry.weth());

        return _getSpotPriceInQuote(oracle, token, pool, weth);
    }

    function _getSpotPriceInQuote(
        ISpotPriceOracle oracle,
        address token,
        address pool,
        address quoteToken
    ) internal returns (uint256 price) {
        // Retrieve the spot price with weth as the requested quote token
        (uint256 rawPrice, address actualQuoteToken) = oracle.getSpotPrice(token, pool, quoteToken);

        return _enforceQuoteToken(quoteToken, actualQuoteToken, rawPrice);
    }

    /// @inheritdoc IRootPriceOracle
    /// @dev Getting major "Stack too deep" errors, so if you see locals not abstracted that's why
    function getRangePricesLP(
        address lpToken,
        address pool,
        address quoteToken
    ) external returns (uint256 spotPriceInQuote, uint256 safePriceInQuote, bool isSpotSafe) {
        ISpotPriceOracle spotPriceOracle = _checkSpotOracleRegistration(pool);

        // Retrieve the reserves info for calculations
        (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) =
            spotPriceOracle.getSafeSpotPriceInfo(pool, lpToken, quoteToken);

        // if lp supply is 0 (while we hold it) means compromised pool, so return 0 for worth (and false for safety)
        uint256 nTokens = reserves.length;
        if (nTokens == 0) {
            revert Errors.InvalidParam("reserves");
        }
        if (totalLPSupply == 0) {
            return (0, 0, false);
        }

        isSpotSafe = true; // default to true, and set to false if any threshold is breached in the loop below

        // loop through reserves, and sum up aggregates

        for (uint256 i = 0; i < nTokens; ++i) {
            ISpotPriceOracle.ReserveItemInfo memory reserve = reserves[i];

            uint256 threshold = safeSpotPriceThresholds[reserve.token];
            if (threshold == 0) revert NoThresholdFound(reserve.token);

            uint256 safePrice = getPriceInQuote(reserve.token, quoteToken);
            uint256 spotPrice = _enforceQuoteToken(quoteToken, reserve.actualQuoteToken, reserve.rawSpotPrice);

            //
            // check thresholds to see if spot is safe
            // NOTE: narrowing scope to avoid "stack too deep" errors
            //
            {
                (uint256 largerPrice, uint256 smallerPrice) =
                    (safePrice > spotPrice) ? (safePrice, spotPrice) : (spotPrice, safePrice);
                uint256 priceDiff = largerPrice - smallerPrice;

                if (largerPrice == 0 || (priceDiff * THRESHOLD_PRECISION / largerPrice) > threshold) {
                    isSpotSafe = false; // validate that the spot price is safe
                }
            }

            //
            // add to totals (with padding to quoteToken decimals)
            uint256 reserveTokenBaseDecimals = 10 ** IERC20Metadata(reserve.token).decimals();
            safePriceInQuote += reserve.reserveAmount * safePrice / reserveTokenBaseDecimals;
            spotPriceInQuote += reserve.reserveAmount * spotPrice / reserveTokenBaseDecimals;
        }

        //
        // divide by total lp supply to get price per lp token
        uint256 lpTokenDecimalsPad = 10 ** IERC20Metadata(lpToken).decimals();
        safePriceInQuote = safePriceInQuote * lpTokenDecimalsPad / totalLPSupply;
        spotPriceInQuote = spotPriceInQuote * lpTokenDecimalsPad / totalLPSupply;
    }

    /// @dev if quote token returned is not the requested one, do price conversion
    function _enforceQuoteToken(
        address quoteToken,
        address actualQuoteToken,
        uint256 rawPrice
    ) internal returns (uint256) {
        // If quote token returned is the requested one we return price as is
        if (actualQuoteToken == quoteToken) {
            return rawPrice;
        }

        uint256 decimals = IERC20Metadata(actualQuoteToken).decimals();

        // If not, get the conversion rate from the actualQuoteToken to quoteToken and then derive the spot price
        return rawPrice * getPriceInQuote(actualQuoteToken, quoteToken) / 10 ** decimals;
    }

    ///@inheritdoc IRootPriceOracle
    function getPriceInQuote(address base, address quote) public returns (uint256) {
        IPriceOracle baseOracle = _checkTokenOracleRegistration(base);

        uint256 quoteDecimals = IERC20Metadata(quote).decimals();
        if (base == quote) {
            return 1 * 10 ** quoteDecimals;
        }

        // No need to go through the extra math if we're asking for it in terms we already have
        uint256 baseInEth = baseOracle.getPriceInEth(base);
        if (quote == _weth) {
            return baseInEth;
        }

        IPriceOracle quoteOracle = _checkTokenOracleRegistration(quote);

        return (baseInEth * (10 ** quoteDecimals)) / quoteOracle.getPriceInEth(quote);
    }

    function _checkTokenOracleRegistration(
        address token
    ) private view returns (IPriceOracle oracle) {
        oracle = tokenMappings[token];
        if (address(oracle) == address(0)) {
            revert MissingTokenOracle(token);
        }
    }

    function _checkSpotOracleRegistration(
        address pool
    ) private view returns (ISpotPriceOracle spotOracle) {
        spotOracle = poolMappings[pool];
        if (address(spotOracle) == address(0)) {
            revert MissingSpotPriceOracle(pool);
        }
    }

    /**
     * @notice Get the floor price of a token in quote token denomination.
     * @param lpToken Address of the token.
     * @param pool Address of the pool.
     * @param quote Address of the quote token.
     * @return price Price of token in quote token.
     */
    function getFloorPrice(address lpToken, address pool, address quote) external returns (uint256 price) {
        price = getFloorCeilingPrice(pool, lpToken, quote, false);
    }

    /**
     * @notice Get the ceiling price of a token in quote token denomination.
     * @param lpToken Address of the token.
     * @param pool Address of the pool.
     * @param quote Address of the quote token.
     * @return price Price of token in quote token.
     */
    function getCeilingPrice(address lpToken, address pool, address quote) external returns (uint256 price) {
        price = getFloorCeilingPrice(pool, lpToken, quote, true);
    }
}
