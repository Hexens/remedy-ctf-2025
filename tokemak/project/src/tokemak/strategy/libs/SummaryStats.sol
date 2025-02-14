// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { IIncentivesPricingStats } from "src/tokemak/interfaces/stats/IIncentivesPricingStats.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { IStrategy } from "src/tokemak/interfaces/strategy/IStrategy.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { StrategyUtils } from "src/tokemak/strategy/libs/StrategyUtils.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { Incentives } from "src/tokemak/strategy/libs/Incentives.sol";
import { PriceReturn } from "src/tokemak/strategy/libs/PriceReturn.sol";
import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ISummaryStatsHook } from "src/tokemak/interfaces/strategy/ISummaryStatsHook.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SubSaturateMath } from "src/tokemak/strategy/libs/SubSaturateMath.sol";

library SummaryStats {
    using SubSaturateMath for uint256;

    error StaleData(string name);
    error LstStatsReservesMismatch();

    event InLSTPriceGap(address token, uint256 priceSafe, uint256 priceSpot);
    event OutLSTPriceGap(address token, uint256 priceSafe, uint256 priceSpot);

    struct InterimStats {
        uint256 baseApr;
        int256 priceReturn;
        int256 maxDiscount;
        int256 maxPremium;
        uint256 reservesTotal;
        int256[] priceReturns;
        uint256 numLstStats;
    }

    struct RebalanceValueStats {
        uint256 inPrice;
        uint256 outPrice;
        uint256 inEthValue;
        uint256 outEthValue;
        uint256 swapCost;
        uint256 slippage;
    }

    function getDestinationSummaryStats(
        IAutopool autoPool,
        IIncentivesPricingStats incentivePricing,
        address destAddress,
        uint256 price,
        IAutopoolStrategy.RebalanceDirection direction,
        uint256 amount
    ) external returns (IStrategy.SummaryStats memory) {
        // NOTE: creating this as empty to save on variables later
        // has the distinct downside that if you forget to update a value, you get the zero value
        // slither-disable-next-line uninitialized-local
        IStrategy.SummaryStats memory result;

        if (destAddress == address(autoPool)) {
            result.destination = destAddress;
            result.ownedShares = autoPool.getAssetBreakdown().totalIdle;
            result.pricePerShare = price;
            return result;
        }

        IDestinationVault dest = IDestinationVault(destAddress);
        IDexLSTStats.DexLSTStatsData memory stats = dest.getStats().current();

        ensureNotStaleData("DexStats", stats.lastSnapshotTimestamp);

        // temporary holder to reduce variables
        InterimStats memory interimStats;

        interimStats.numLstStats = stats.lstStatsData.length;
        if (interimStats.numLstStats != stats.reservesInEth.length) revert LstStatsReservesMismatch();

        interimStats.priceReturns = PriceReturn.calculatePriceReturns(stats);

        for (uint256 i = 0; i < interimStats.numLstStats; ++i) {
            uint256 reserveValue = stats.reservesInEth[i];
            interimStats.reservesTotal += reserveValue;

            if (interimStats.priceReturns[i] != 0) {
                interimStats.priceReturn +=
                    PriceReturn.calculateWeightedPriceReturn(interimStats.priceReturns[i], reserveValue, direction);
            }

            // For tokens like WETH/ETH who have no data, tokens we've configured as NO_OP's in the
            // destinations/calculators, we can just skip the rest of these calcs as they have no stats
            if (stats.lstStatsData[i].baseApr == 0 && stats.lstStatsData[i].lastSnapshotTimestamp == 0) {
                continue;
            }

            ensureNotStaleData("lstData", stats.lstStatsData[i].lastSnapshotTimestamp);

            interimStats.baseApr += stats.lstStatsData[i].baseApr * reserveValue;

            int256 discount = stats.lstStatsData[i].discount;
            // slither-disable-next-line timestamp
            if (discount < interimStats.maxPremium) {
                interimStats.maxPremium = discount;
            }
            // slither-disable-next-line timestamp
            if (discount > interimStats.maxDiscount) {
                interimStats.maxDiscount = discount;
            }
        }

        // if reserves are 0, then leave baseApr + priceReturn as 0
        if (interimStats.reservesTotal > 0) {
            result.baseApr = interimStats.baseApr / interimStats.reservesTotal;
            result.priceReturn = interimStats.priceReturn / StrategyUtils.convertUintToInt(interimStats.reservesTotal);
        }

        result.destination = destAddress;
        result.feeApr = stats.feeApr;
        result.incentiveApr = Incentives.calculateIncentiveApr(
            incentivePricing, stats.stakingIncentiveStats, direction, destAddress, amount, price
        );
        result.safeTotalSupply = stats.stakingIncentiveStats.safeTotalSupply;
        result.ownedShares = dest.balanceOf(address(autoPool));
        result.pricePerShare = price;
        result.maxPremium = interimStats.maxPremium;
        result.maxDiscount = interimStats.maxDiscount;

        // Manipulate SummaryStats by hooks if there are registered hooks.  If not this returns result as is
        result = _getHookResults(result, autoPool, destAddress, price, direction, amount);

        uint256 returnExPrice = (
            result.baseApr * IAutopoolStrategy(address(this)).weightBase() / 1e6
                + result.feeApr * IAutopoolStrategy(address(this)).weightFee() / 1e6
                + result.incentiveApr * IAutopoolStrategy(address(this)).weightIncentive() / 1e6
        );

        // price already weighted
        result.compositeReturn = StrategyUtils.convertUintToInt(returnExPrice) + result.priceReturn;

        return result;
    }

    function getRebalanceValueStats(
        IStrategy.RebalanceParams memory params,
        address autoPoolAddress
    ) external returns (RebalanceValueStats memory) {
        uint8 tokenOutDecimals = IERC20Metadata(params.tokenOut).decimals();
        uint8 tokenInDecimals = IERC20Metadata(params.tokenIn).decimals();

        // Prices are all in terms of the base asset, so when its a rebalance back to the vault
        // or out of the vault, We can just take things as 1:1

        // Get the price of one unit of the underlying lp token, the params.tokenOut/tokenIn
        // Prices are calculated using the spot of price of the constituent tokens
        // validated to be within a tolerance of the safe price of those tokens
        uint256 outPrice = params.destinationOut != autoPoolAddress
            ? IDestinationVault(params.destinationOut).getValidatedSpotPrice()
            : 10 ** tokenOutDecimals;

        uint256 inPrice = params.destinationIn != autoPoolAddress
            ? IDestinationVault(params.destinationIn).getValidatedSpotPrice()
            : 10 ** tokenInDecimals;

        // prices are 1e18 and we want values in 1e18, so divide by token decimals
        uint256 outEthValue = params.destinationOut != autoPoolAddress
            ? outPrice * params.amountOut / 10 ** tokenOutDecimals
            : params.amountOut;

        // amountIn is a minimum to receive, but it is OK if we receive more
        uint256 inEthValue = params.destinationIn != autoPoolAddress
            ? inPrice * params.amountIn / 10 ** tokenInDecimals
            : params.amountIn;

        uint256 swapCost = outEthValue.subSaturate(inEthValue);
        uint256 slippage = outEthValue == 0 ? 0 : swapCost * 1e18 / outEthValue;

        return RebalanceValueStats({
            inPrice: inPrice,
            outPrice: outPrice,
            inEthValue: inEthValue,
            outEthValue: outEthValue,
            swapCost: swapCost,
            slippage: slippage
        });
    }

    // Calculate the largest difference between spot & safe price for the underlying LST tokens.
    // This does not support Curve meta pools
    function verifyLSTPriceGap(
        IAutopool autoPool,
        IStrategy.RebalanceParams memory params,
        uint256 tolerance
    ) external returns (bool) {
        // Pricer
        ISystemRegistry registry = ISystemRegistry(ISystemComponent(address(this)).getSystemRegistry());
        IRootPriceOracle pricer = registry.rootPriceOracle();

        IDestinationVault dest;
        address[] memory lstTokens;
        uint256 numLsts;
        address dvPoolAddress;

        // Out Destination
        if (params.destinationOut != address(autoPool)) {
            dest = IDestinationVault(params.destinationOut);
            lstTokens = dest.underlyingTokens();
            numLsts = lstTokens.length;
            dvPoolAddress = dest.getPool();
            for (uint256 i = 0; i < numLsts; ++i) {
                uint256 priceSafe = pricer.getPriceInEth(lstTokens[i]);
                uint256 priceSpot = pricer.getSpotPriceInEth(lstTokens[i], dvPoolAddress);
                // slither-disable-next-line reentrancy-events
                emit OutLSTPriceGap(lstTokens[i], priceSafe, priceSpot);
                // For out destination, the pool tokens should not be lower than safe price by tolerance
                if ((priceSafe == 0) || (priceSpot == 0)) {
                    return false;
                } else if (priceSafe > priceSpot) {
                    if (((priceSafe * 1.0e18 / priceSpot - 1.0e18) * 10_000) / 1.0e18 > tolerance) {
                        return false;
                    }
                }
            }
        }

        // In Destination
        dest = IDestinationVault(params.destinationIn);
        lstTokens = dest.underlyingTokens();
        numLsts = lstTokens.length;
        dvPoolAddress = dest.getPool();
        for (uint256 i = 0; i < numLsts; ++i) {
            uint256 priceSafe = pricer.getPriceInEth(lstTokens[i]);
            uint256 priceSpot = pricer.getSpotPriceInEth(lstTokens[i], dvPoolAddress);
            // slither-disable-next-line reentrancy-events
            emit InLSTPriceGap(lstTokens[i], priceSafe, priceSpot);
            // For in destination, the pool tokens should not be higher than safe price by tolerance
            if ((priceSafe == 0) || (priceSpot == 0)) {
                return false;
            } else if (priceSpot > priceSafe) {
                if (((priceSpot * 1.0e18 / priceSafe - 1.0e18) * 10_000) / 1.0e18 > tolerance) {
                    return false;
                }
            }
        }

        return true;
    }

    function ensureNotStaleData(string memory name, uint256 dataTimestamp) internal view {
        // slither-disable-next-line timestamp
        if (block.timestamp - dataTimestamp > IAutopoolStrategy(address(this)).staleDataToleranceInSeconds()) {
            revert StaleData(name);
        }
    }

    /// @dev Used to apply any manipulations to destinations stats via hooks
    function _getHookResults(
        IStrategy.SummaryStats memory _result,
        IAutopool autopool,
        address destAddress,
        uint256 price,
        IAutopoolStrategy.RebalanceDirection direction,
        uint256 amount
    ) private returns (IStrategy.SummaryStats memory result) {
        result = _result;

        address[] memory hooks = IAutopoolStrategy(address(this)).getHooks();
        for (uint256 i = 0; i < hooks.length; ++i) {
            address currentHook = hooks[i];
            if (currentHook == address(0)) break;

            result = ISummaryStatsHook(currentHook).execute(result, autopool, destAddress, price, direction, amount);
        }
    }
}
