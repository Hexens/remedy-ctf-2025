// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { IPool } from "src/tokemak/interfaces/external/maverick/IPool.sol";
import { IPoolPositionSlim } from "src/tokemak/interfaces/external/maverick/IPoolPositionSlim.sol";
import { Stats } from "src/tokemak/stats/Stats.sol";
import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";
import { IMaverickFeeAprOracle } from "src/tokemak/interfaces/oracles/IMaverickFeeAprOracle.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MaverickDexCalculator is IDexLSTStats, BaseStatsCalculator {
    uint256 public lastSnapshotTimestamp;

    ILSTStats[2] public lstStats;
    uint256 public dexReserveAlpha;

    IPool public pool;
    IPoolPositionSlim public boostedPosition;
    IMaverickFeeAprOracle public feeAprOracle;

    address[2] public reserveTokens;
    uint256[2] public reserveTokensDecimals;
    uint256[2] public reservesInEth;
    bytes32 private _aprId;

    bool public reservesInEthFilterInitialized;
    bool public feeAprFilterInitialized;

    uint256 public feeApr;

    struct InitData {
        address pool;
        address boostedPosition;
        uint256 dexReserveAlpha;
        address feeAprOracle;
    }

    error DependentAprIdsNot2();
    error BoostedPositionPoolDoesNotMatchInitPool();

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseStatsCalculator(_systemRegistry) { }

    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.pool, "pool");
        Errors.verifyNotZero(decodedInitData.boostedPosition, "boostedPosition");
        Errors.verifyNotZero(decodedInitData.dexReserveAlpha, "dexReserveAlpha");
        Errors.verifyNotZero(decodedInitData.feeAprOracle, "feeAprOracle");

        if (decodedInitData.pool != address(IPoolPositionSlim(decodedInitData.boostedPosition).pool())) {
            revert BoostedPositionPoolDoesNotMatchInitPool();
        }

        pool = IPool(decodedInitData.pool);
        boostedPosition = IPoolPositionSlim(decodedInitData.boostedPosition);
        feeAprOracle = IMaverickFeeAprOracle(decodedInitData.feeAprOracle);
        dexReserveAlpha = decodedInitData.dexReserveAlpha;

        address tokenA = address(pool.tokenA());
        address tokenB = address(pool.tokenB());
        reserveTokens[0] = tokenA;
        reserveTokens[1] = tokenB;

        reserveTokensDecimals[0] = IERC20Metadata(tokenA).decimals();
        reserveTokensDecimals[1] = IERC20Metadata(tokenB).decimals();

        _aprId = keccak256(abi.encode("maverick", pool, boostedPosition));

        if (dependentAprIds.length != 2) {
            revert DependentAprIdsNot2();
        }

        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();

        for (uint256 i = 0; i < 2; ++i) {
            bytes32 dependentAprId = dependentAprIds[i];
            address coin = reserveTokens[i];
            Errors.verifyNotZero(coin, "coin");

            if (dependentAprId != Stats.NOOP_APR_ID) {
                IStatsCalculator calculator = registry.getCalculator(dependentAprId);

                // Ensure that the calculator we configured is meant to handle the token
                // setup on the pool. Individual token calculators use the address of the token
                // itself as the address id
                if (calculator.getAddressId() != coin) {
                    revert Stats.CalculatorAssetMismatch(dependentAprId, address(calculator), coin);
                }

                ILSTStats stats = ILSTStats(address(calculator));
                lstStats[i] = stats;
            }
        }
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view virtual override returns (bool takeSnapshot) {
        // snapshot both dex reserves and fee apr at the same time.
        // slither-disable-next-line timestamp
        takeSnapshot = (block.timestamp - lastSnapshotTimestamp) > Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return address(boostedPosition);
    }

    function _getCurrentReservesInEth() internal returns (uint256, uint256) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        (uint256 reservesA, uint256 reservesB) = IPoolPositionSlim(boostedPosition).getReserves();

        uint256[] memory balances = new uint256[](2);
        balances[0] = reservesA;
        balances[1] = reservesB;

        // slither-disable-start similar-names
        uint256 reservesAEthValue = calculateReserveInEthByIndex(pricer, balances, 0);
        uint256 reservesBEthValue = calculateReserveInEthByIndex(pricer, balances, 1);

        return (reservesAEthValue, reservesBEthValue);
        // slither-disable-end similar-names
    }

    function _snapshot() internal override {
        // slither-disable-next-line similar-names
        (uint256 reservesAEthValue, uint256 reservesBEthValue) = _getCurrentReservesInEth();

        if (reservesInEthFilterInitialized) {
            // filter normally once the filter has been initialized
            reservesInEth[0] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[0], reservesAEthValue);
            reservesInEth[1] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[1], reservesBEthValue);
        } else {
            // first raw sample is used to initialize the filter
            reservesInEth[0] = reservesAEthValue;
            reservesInEth[1] = reservesBEthValue;
            reservesInEthFilterInitialized = true;
        }

        uint256 currentFeeApr = feeAprOracle.getFeeApr(address(boostedPosition));

        if (feeAprFilterInitialized) {
            // filter normally once the filter has been initialized
            feeApr = Stats.getFilteredValue(Stats.DEX_FEE_ALPHA, feeApr, currentFeeApr);
        } else {
            // first raw sample is used to initialize the filter
            feeApr = currentFeeApr;
            feeAprFilterInitialized = true;
        }
        lastSnapshotTimestamp = block.timestamp;
    }

    function calculateReserveInEthByIndex(
        IRootPriceOracle pricer,
        uint256[] memory balances,
        uint256 index
    ) internal returns (uint256) {
        address token = reserveTokens[index];

        // We are using the balances directly here which can be manipulated but these values are
        // only used in the strategy where we do additional checks to ensure the pool
        // is a good state
        // We don't have to check decimals here because Maverick Pools getReserves() scales token reserves to 1e18
        // so instead we only need to devide by 1e18 to get the ETH value in 1e18 terms.
        // slither-disable-next-line reentrancy-benign,reentrancy-no-eth
        return pricer.getPriceInEth(token) * balances[index] / 1e18;
    }

    /// @inheritdoc IDexLSTStats
    function current() external returns (DexLSTStatsData memory) {
        ILSTStats.LSTStatsData[] memory lstStatsData = new ILSTStats.LSTStatsData[](2);
        // address(0) is for WETH
        if (address(lstStats[0]) != address(0)) {
            lstStatsData[0] = lstStats[0].current();
        }
        if (address(lstStats[1]) != address(0)) {
            lstStatsData[1] = lstStats[1].current();
        }
        // slither-disable-next-line similar-names
        (uint256 reservesAEthValue, uint256 reservesBEthValue) = _getCurrentReservesInEth();

        uint256[] memory reservesInEthMemory = new uint256[](2);

        reservesInEthMemory[0] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[0], reservesAEthValue);
        reservesInEthMemory[1] = Stats.getFilteredValue(dexReserveAlpha, reservesInEth[1], reservesBEthValue);

        //slither-disable-next-line uninitialized-local
        StakingIncentiveStats memory stakingIncentiveStats;

        return DexLSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            feeApr: feeApr,
            lstStatsData: lstStatsData,
            reservesInEth: reservesInEthMemory,
            stakingIncentiveStats: stakingIncentiveStats
        });
    }
}
