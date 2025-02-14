// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IPool } from "src/tokemak/interfaces/external/maverick/IPool.sol";
import { IPoolPositionDynamicSlim } from "src/tokemak/interfaces/external/maverick/IPoolPositionDynamicSlim.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Utilities } from "src/tokemak/libs/Utilities.sol";
import { ISpotPriceOracle } from "src/tokemak/interfaces/oracles/ISpotPriceOracle.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { IPoolInformation } from "src/tokemak/interfaces/external/maverick/IPoolInformation.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

//slither-disable-start similar-names
contract MavEthOracle is SystemComponent, SecurityBase, ISpotPriceOracle {
    /// @notice Emitted when Maverick PoolInformation contract is set.
    event PoolInformationSet(address poolInformation);

    /// @notice Thrown when token is not in pool.
    error InvalidToken();

    /// @notice The PoolInformation Maverick contract.
    IPoolInformation public poolInformation;

    constructor(
        ISystemRegistry _systemRegistry,
        address _poolInformation
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "priceOracle");

        Errors.verifyNotZero(_poolInformation, "_poolInformation");
        poolInformation = IPoolInformation(_poolInformation);
    }

    /// @inheritdoc ISpotPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "mav";
    }

    /// @notice Gives ability to set PoolInformation
    function setPoolInformation(
        address _poolInformation
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(_poolInformation, "_poolInformation");
        poolInformation = IPoolInformation(_poolInformation);

        emit PoolInformationSet(_poolInformation);
    }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address poolAddress,
        address
    ) public returns (uint256 price, address actualQuoteToken) {
        Errors.verifyNotZero(poolAddress, "poolAddress");

        IPool pool = IPool(poolAddress);

        address tokenA = address(pool.tokenA());
        address tokenB = address(pool.tokenB());

        // Determine if the input token is tokenA
        bool isTokenA = token == tokenA;

        // Determine actualQuoteToken as the opposite of the input token
        actualQuoteToken = isTokenA ? tokenB : tokenA;

        // Validate if the input token is either tokenA or tokenB
        if (!isTokenA && token != tokenB) revert InvalidToken();

        price = _getSpotPrice(token, pool, isTokenA);
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address _boostedPosition,
        address // we omit quoteToken as we get pricing info from the pool.
            // It's aligned with the requested quoteToken in RootPriceOracle.getRangePricesLP
    ) external returns (uint256 totalLPSupply, ISpotPriceOracle.ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(_boostedPosition, "_boostedPosition");

        IPool mavPool = IPool(pool);
        IPoolPositionDynamicSlim boostedPosition = IPoolPositionDynamicSlim(_boostedPosition);

        // Get total supply of lp tokens from boosted position
        totalLPSupply = boostedPosition.totalSupply();

        // Get tokens pool tokens
        address tokenA = address(mavPool.tokenA());
        address tokenB = address(mavPool.tokenB());

        // Get reserves in boosted position
        (uint256 reserveTokenA, uint256 reserveTokenB) = boostedPosition.getReserves();

        //getReserves scales to 18, so we need to scale back to token decimals
        (reserveTokenA, reserveTokenB) = (
            _scaleDecimalsToOriginal(IERC20Metadata(tokenA), reserveTokenA),
            _scaleDecimalsToOriginal(IERC20Metadata(tokenB), reserveTokenB)
        );

        reserves = new ISpotPriceOracle.ReserveItemInfo[](2);
        reserves[0] = ISpotPriceOracle.ReserveItemInfo({
            token: tokenA,
            reserveAmount: reserveTokenA,
            rawSpotPrice: _getSpotPrice(tokenA, mavPool, true),
            actualQuoteToken: tokenB
        });
        reserves[1] = ISpotPriceOracle.ReserveItemInfo({
            token: tokenB,
            reserveAmount: reserveTokenB,
            rawSpotPrice: _getSpotPrice(tokenB, mavPool, false),
            actualQuoteToken: tokenA
        });
    }

    /// @dev This function gets price using Maverick's `PoolInformation` contract
    function _getSpotPrice(address token, IPool pool, bool isTokenA) private returns (uint256 price) {
        (uint256 downScaledUnit, uint256 padUnit) = Utilities.getScaleDownFactor(IERC20Metadata(token).decimals());

        price = poolInformation.calculateSwap(
            pool,
            // we swap scaled-down units to minimize the impact on small pools
            uint128(downScaledUnit),
            isTokenA, // tokenAIn
            false, // exactOutput
            0 // sqrtPriceLimit
        );

        // Maverick Fee is in 1e18.
        // We scale up the price by 1000 (1e21) so the returned price is in 1 unit
        // https://docs.mav.xyz/guides/technical-reference/pool#fn-fee
        price = (price * (1e18 * padUnit)) / (1e18 - pool.fee());
    }

    ///@dev Scale decimals back to original value from 1e18
    function _scaleDecimalsToOriginal(IERC20Metadata token, uint256 amount) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(token).decimals();

        if (decimals == 18) {
            return amount;
        } else if (decimals < 18) {
            uint256 exponent = 18 - decimals;
            amount = amount / (10 ** exponent);
        } else {
            uint256 exponent = decimals - 18;
            amount = amount * (10 ** exponent);
        }

        return amount;
    }
}
//slither-disable-end similar-names
