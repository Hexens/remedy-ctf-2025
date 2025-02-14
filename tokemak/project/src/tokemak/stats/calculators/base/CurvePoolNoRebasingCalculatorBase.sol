// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Stats } from "src/tokemak/stats/Stats.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";
import { ICurveResolver } from "src/tokemak/interfaces/utils/ICurveResolver.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { IPool } from "src/tokemak/interfaces/external/curve/IPool.sol";
import { CurveUtils } from "src/tokemak/stats/utils/CurveUtils.sol";

/// @title Curve Pool No Rebasing Calculator Base
/// @notice Generates stats for Curve pools that do not include any rebasing tokens
/// @dev Contract is cheaper to snapshot because it tracks less state on snapshots
abstract contract CurvePoolNoRebasingCalculatorBase is IDexLSTStats, BaseStatsCalculator {
    /// @notice The stats contracts for the underlying LSTs
    /// @return the LST stats contract for the specified index
    ILSTStats[] public lstStats;

    /// @notice The addresses of the pools reserve tokens
    /// @return the reserve token address for the specified index
    address[] public reserveTokens;

    /// @notice The number of underlying tokens in the pool
    uint256 public numTokens;

    /// @notice The Curve pool address that the stats are for
    address public poolAddress;

    /// @notice The LP token for the Curve pool. May be the same as pool address
    address public lpToken;

    /// @notice The most recent filtered feeApr. Typically retrieved via the current method
    uint256 public feeApr;

    /// @notice Flag indicating if the feeApr filter is initialized
    bool public feeAprFilterInitialized;

    /// @notice The last time a snapshot was taken
    uint256 public lastSnapshotTimestamp;

    /// @notice The pool's virtual price the last time a snapshot was taken
    uint256 public lastVirtualPrice;

    bytes32 private _aprId;

    struct InitData {
        address poolAddress;
    }

    error DependentAprIdsMismatchTokens(uint256 numDependentAprIds, uint256 numCoins);
    error InvalidPool(address poolAddress);

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseStatsCalculator(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return lpToken;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));
        Errors.verifyNotZero(decodedInitData.poolAddress, "poolAddress");
        poolAddress = decodedInitData.poolAddress;

        ICurveResolver curveResolver = systemRegistry.curveResolver();
        // slither-disable-next-line unused-return
        (reserveTokens, numTokens, lpToken,) = curveResolver.resolveWithLpToken(poolAddress);

        Errors.verifyNotZero(lpToken, "lpToken");
        if (numTokens == 0) {
            revert InvalidPool(poolAddress);
        }

        // We should have the same number of calculators sent in as there are coins
        if (dependentAprIds.length != numTokens) {
            revert DependentAprIdsMismatchTokens(dependentAprIds.length, numTokens);
        }

        _aprId = Stats.generateCurvePoolIdentifier(poolAddress);

        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();
        lstStats = new ILSTStats[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            bytes32 dependentAprId = dependentAprIds[i];
            address coin = reserveTokens[i];

            if (dependentAprId != Stats.NOOP_APR_ID) {
                IStatsCalculator calculator = registry.getCalculator(dependentAprId);

                // Ensure that the calculator we configured is meant to handle the token
                // setup on the pool. Individual token calculators use the address of the token
                // itself as the address id
                if (calculator.getAddressId() != coin) {
                    revert Stats.CalculatorAssetMismatch(dependentAprId, address(calculator), coin);
                }

                lstStats[i] = ILSTStats(address(calculator));
            }

            // call now to revert at init if there is an issue b/c this call is made in other calculations
            // slither-disable-next-line unused-return
            CurveUtils.getDecimals(coin);
        }

        lastSnapshotTimestamp = block.timestamp;
        lastVirtualPrice = getVirtualPrice();
        feeAprFilterInitialized = false;
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view override returns (bool) {
        if (feeAprFilterInitialized) {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastSnapshotTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        } else {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastSnapshotTimestamp + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        }
    }

    /// @inheritdoc IDexLSTStats
    function current() external returns (DexLSTStatsData memory) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        ILSTStats.LSTStatsData[] memory lstStatsData = new ILSTStats.LSTStatsData[](numTokens);

        uint256[] memory reservesInEth = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            address token = reserveTokens[i];

            // the price oracle is always 18 decimals, so divide by the decimals of the token
            // to ensure that we always report the value in ETH as 18 decimals
            uint256 priceDivisor = 10 ** CurveUtils.getDecimals(token);

            // We are using the balances directly here which can be manipulated but these values are
            // only used in the strategy where we do additional checks to ensure the pool
            // is a good state
            reservesInEth[i] = pricer.getPriceInEth(token) * IPool(poolAddress).balances(i) / priceDivisor;

            if (address(lstStats[i]) != address(0)) {
                lstStatsData[i] = lstStats[i].current();
            }
        }

        // we want to return zero values
        // slither-disable-next-line uninitialized-local
        StakingIncentiveStats memory stakingIncentiveStats;

        return DexLSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            feeApr: feeApr,
            lstStatsData: lstStatsData,
            reservesInEth: reservesInEth,
            stakingIncentiveStats: stakingIncentiveStats
        });
    }

    /// @notice Capture stat data about this setup
    /// @dev This is protected by the STATS_SNAPSHOT_EXECUTOR
    function _snapshot() internal override {
        uint256 currentVirtualPrice = getVirtualPrice();

        uint256 currentFeeApr = Stats.calculateAnnualizedChangeMinZero(
            lastSnapshotTimestamp, lastVirtualPrice, block.timestamp, currentVirtualPrice
        );

        uint256 newFeeApr;
        if (feeAprFilterInitialized) {
            // filter normally once the filter has been initialized
            newFeeApr = Stats.getFilteredValue(Stats.DEX_FEE_ALPHA, feeApr, currentFeeApr);
        } else {
            // first raw sample is used to initialize the filter
            newFeeApr = currentFeeApr;
            feeAprFilterInitialized = true;
        }

        emit DexSnapshotTaken(block.timestamp, feeApr, newFeeApr, currentFeeApr);

        lastSnapshotTimestamp = block.timestamp;
        lastVirtualPrice = currentVirtualPrice;
        feeApr = newFeeApr;
    }

    function getVirtualPrice() internal virtual returns (uint256 virtualPrice);
}
