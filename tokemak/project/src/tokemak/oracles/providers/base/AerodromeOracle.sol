// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Utilities } from "src/tokemak/libs/Utilities.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ISpotPriceOracle } from "src/tokemak/interfaces/oracles/ISpotPriceOracle.sol";
import { IPool } from "src/tokemak/interfaces/external/aerodrome/IPool.sol";
import { IPoolFactory } from "src/tokemak/interfaces/external/aerodrome/IPoolFactory.sol";

contract AerodromeOracle is SystemComponent, ISpotPriceOracle {
    error InvalidPool(address pool);

    uint256 private constant FEE_PRECISION = 10_000;

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) { }

    /// @inheritdoc ISpotPriceOracle
    function getSpotPrice(
        address token,
        address pool,
        address
    ) external view returns (uint256 price, address quoteToken) {
        Errors.verifyNotZero(token, "token");
        Errors.verifyNotZero(pool, "pool");

        IPool poolContract = IPool(pool);

        // slither-disable-start similar-names
        address token0 = poolContract.token0();
        address token1 = poolContract.token1();
        // slither-disable-end similar-names

        if (token != token0 && token != token1) {
            revert InvalidPool(pool);
        }
        quoteToken = token == token0 ? token1 : token0;

        price = _getSpotPrice(token, pool);
    }

    /// @inheritdoc ISpotPriceOracle
    function getSafeSpotPriceInfo(
        address pool,
        address lpToken,
        address
    ) external view returns (uint256 totalLPSupply, ReserveItemInfo[] memory reserves) {
        Errors.verifyNotZero(pool, "pool");
        Errors.verifyNotZero(lpToken, "lpToken");

        IPool poolContract = IPool(pool);
        totalLPSupply = IERC20(lpToken).totalSupply();

        // slither-disable-start similar-names
        (address tokenA, address tokenB) = poolContract.tokens();
        uint256 reserveA = poolContract.reserve0();
        uint256 reserveB = poolContract.reserve1();

        uint256 rawSpotPriceA = _getSpotPrice(tokenA, pool);
        uint256 rawSpotPriceB = _getSpotPrice(tokenB, pool);

        reserves = new ReserveItemInfo[](2);
        reserves[0] = ReserveItemInfo(tokenA, reserveA, rawSpotPriceA, tokenB);
        reserves[1] = ReserveItemInfo(tokenB, reserveB, rawSpotPriceB, tokenA);
        // slither-disable-end similar-names
    }

    function _getSpotPrice(address token, address pool) internal view returns (uint256 price) {
        IPool poolContract = IPool(pool);
        (uint256 downScaledUnit, uint256 padUnit) = Utilities.getScaleDownFactor(IERC20Metadata(token).decimals());
        price = poolContract.getAmountOut(downScaledUnit, token) * padUnit;
        uint256 fee = IPoolFactory(poolContract.factory()).getFee(address(poolContract), poolContract.stable());
        price = (price * FEE_PRECISION) / (FEE_PRECISION - fee);
    }

    /// @inheritdoc ISpotPriceOracle
    function getDescription() external pure returns (string memory) {
        return "aerodrome";
    }
}
