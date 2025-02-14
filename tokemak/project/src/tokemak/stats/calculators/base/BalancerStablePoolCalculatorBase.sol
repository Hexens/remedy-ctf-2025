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
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/tokemak/interfaces/external/balancer/IBalancerPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title Balancer Stable Pool Calculator Base
/// @notice Generates stats for Balancer Stable pools
abstract contract BalancerStablePoolCalculatorBase is IDexLSTStats, BaseStatsCalculator {
    /// @notice The configured vault address
    IVault public immutable balancerVault;

    /// @notice The stats contracts for the underlying LSTs
    /// @return the LST stats contract for the specified index
    ILSTStats[] public lstStats;

    /// @notice The addresses of the pools reserve tokens
    /// @return the reserve token address for the specified index
    address[] public reserveTokens;

    /// @notice The number of underlying tokens in the pool
    uint256 public numTokens;

    /// @notice The Balancer pool address that the stats are for
    address public poolAddress;

    /// @notice The Balancer pool id that the stats are for
    bytes32 public poolId;

    /// @notice The most recent filtered feeApr. Typically retrieved via the current method
    uint256 public feeApr;

    /// @notice Flag indicating if the feeApr filter is initialized
    bool public feeAprFilterInitialized;

    /// @notice The last time a snapshot was taken
    uint256 public lastSnapshotTimestamp;

    /// @notice The pool's virtual price the last time a snapshot was taken
    uint256 public lastVirtualPrice;

    /// @notice The ethPerShare for the reserve tokens
    uint256[] public lastEthPerShare;

    /// @notice bool for if Balancer takes a portion of the baseApr of LSTs / LRTs
    bool public isExemptFromYieldProtocolFee;

    bytes32 internal _aprId;

    struct InitData {
        address poolAddress;
    }

    error InvalidPool(address poolAddress);
    error InvalidPoolId(address poolAddress);
    error DependentAprIdsMismatchTokens(uint256 numDependentAprIds, uint256 numCoins);

    constructor(ISystemRegistry _systemRegistry, address _balancerVault) BaseStatsCalculator(_systemRegistry) {
        Errors.verifyNotZero(_balancerVault, "_balancerVault");
        balancerVault = IVault(_balancerVault);
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return poolAddress;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IStatsCalculator
    function initialize(
        bytes32[] calldata dependentAprIds,
        bytes calldata initData
    ) external virtual override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.poolAddress, "poolAddress");
        poolAddress = decodedInitData.poolAddress;

        poolId = IBalancerPool(poolAddress).getPoolId();
        if (poolId == bytes32(0)) revert InvalidPoolId(poolAddress);

        // reserveTokens addresses are checked against the dependentAprIds in a later step
        (IERC20[] memory _reserveTokens,) = getPoolTokens();

        numTokens = _reserveTokens.length;
        if (numTokens == 0) {
            revert InvalidPool(poolAddress);
        }

        // We should have the same number of calculators sent in as there are coins
        if (dependentAprIds.length != numTokens) {
            revert DependentAprIdsMismatchTokens(dependentAprIds.length, numTokens);
        }

        _aprId = Stats.generateBalancerPoolIdentifier(poolAddress);

        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();
        lstStats = new ILSTStats[](numTokens);
        reserveTokens = new address[](numTokens);
        lastEthPerShare = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            bytes32 dependentAprId = dependentAprIds[i];
            address coin = address(_reserveTokens[i]);
            Errors.verifyNotZero(coin, "coin");

            reserveTokens[i] = coin;

            // call now to revert at init if there is an issue b/c this call is made in other calculations
            // slither-disable-next-line unused-return
            IERC20Metadata(coin).decimals();

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

                lastEthPerShare[i] = stats.calculateEthPerToken();
            }
        }

        lastSnapshotTimestamp = block.timestamp;
        lastVirtualPrice = getVirtualPrice();
        feeAprFilterInitialized = false;
        isExemptFromYieldProtocolFee = _isExemptFromYieldProtocolFee();
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view virtual override returns (bool) {
        if (feeAprFilterInitialized) {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastSnapshotTimestamp + Stats.DEX_FEE_APR_SNAPSHOT_INTERVAL;
        } else {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastSnapshotTimestamp + Stats.DEX_FEE_APR_FILTER_INIT_INTERVAL;
        }
    }

    /// @inheritdoc IDexLSTStats
    function current() external virtual returns (DexLSTStatsData memory) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        uint256[] memory reservesInEth = new uint256[](numTokens);
        ILSTStats.LSTStatsData[] memory lstStatsData = new ILSTStats.LSTStatsData[](numTokens);

        (, uint256[] memory balances) = getPoolTokens();

        // only read from storage once
        bool treatAsExemptFromYieldProtocolFee = isExemptFromYieldProtocolFee;

        for (uint256 i = 0; i < numTokens; i++) {
            reservesInEth[i] = calculateReserveInEthByIndex(pricer, balances, i, false);
            ILSTStats stats = lstStats[i];
            if (address(stats) != address(0)) {
                ILSTStats.LSTStatsData memory statsData = stats.current();
                if (!treatAsExemptFromYieldProtocolFee) {
                    statsData.baseApr = adjustBaseAprForBalancerYieldProtocolFee(statsData.baseApr);
                }
                lstStatsData[i] = statsData;
            }
        }

        // we want to return zero values
        // slither-disable-next-line uninitialized-local
        StakingIncentiveStats memory stakingIncentiveStats;

        return DexLSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            feeApr: feeApr,
            reservesInEth: reservesInEth,
            lstStatsData: lstStatsData,
            stakingIncentiveStats: stakingIncentiveStats
        });
    }

    /// @notice Capture stat data about this setup
    /// @dev This is protected by the STATS_SNAPSHOT_EXECUTOR
    function _snapshot() internal virtual override {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        uint256 currentVirtualPrice = getVirtualPrice();
        (, uint256[] memory balances) = getPoolTokens();

        uint256[] memory currentEthPerShare = new uint256[](numTokens);
        uint256[] memory reservesInEth = new uint256[](numTokens);

        // subtracting base yield is an approximation b/c it uses the point-in-time reserve balances to estimate the
        // yield earned from the rebasing token. An attacker could shift the balance of the pool, causing us to believe
        // the fee apr is higher or lower.
        // Autopool strategies understand that this signal can be noisy and correct accordingly A price check against an
        // oracle is an option to further mitigate the issue
        uint256 weightedBaseApr = 0;
        uint256 totalReservesInEth = 0;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 reserveValue = calculateReserveInEthByIndex(pricer, balances, i, true);
            reservesInEth[i] = reserveValue;
            totalReservesInEth += reserveValue;

            ILSTStats stats = lstStats[i];
            if (address(stats) != address(0)) {
                uint256 underlyingEthPerShare = stats.calculateEthPerToken();
                currentEthPerShare[i] = underlyingEthPerShare;
                weightedBaseApr += Stats.calculateAnnualizedChangeMinZero(
                    lastSnapshotTimestamp, lastEthPerShare[i], block.timestamp, underlyingEthPerShare
                ) * reserveValue;
            }
        }

        uint256 currentBaseApr = 0;
        if (totalReservesInEth > 0) {
            currentBaseApr = weightedBaseApr / totalReservesInEth;
        }

        if (!isExemptFromYieldProtocolFee) {
            currentBaseApr = adjustBaseAprForBalancerYieldProtocolFee(currentBaseApr);
        }

        uint256 currentFeeApr = Stats.calculateAnnualizedChangeMinZero(
            lastSnapshotTimestamp, lastVirtualPrice, block.timestamp, currentVirtualPrice
        );

        // slither-disable-next-line timestamp
        if (currentFeeApr > currentBaseApr) {
            currentFeeApr -= currentBaseApr;
        } else {
            currentFeeApr = 0;
        }

        uint256 newFeeApr;
        if (feeAprFilterInitialized) {
            // filter normally once the filter has been initialized
            newFeeApr = Stats.getFilteredValue(Stats.DEX_FEE_ALPHA, feeApr, currentFeeApr);
        } else {
            // first raw sample is used to initialize the filter
            newFeeApr = currentFeeApr;
            feeAprFilterInitialized = true;
        }

        // pricer handles reentrancy issues
        // slither-disable-next-line reentrancy-events
        emit DexSnapshotTaken(block.timestamp, feeApr, newFeeApr, currentFeeApr);

        lastSnapshotTimestamp = block.timestamp;
        lastVirtualPrice = currentVirtualPrice;
        lastEthPerShare = currentEthPerShare;
        feeApr = newFeeApr;
    }

    /// @notice Get the reserves of the token at the given index in ETH
    /// @dev Last param is to denote whether you are running in the context of a snapshot or not
    function calculateReserveInEthByIndex(
        IRootPriceOracle pricer,
        uint256[] memory balances,
        uint256 index,
        bool
    ) internal virtual returns (uint256) {
        address token = reserveTokens[index];

        // the price oracle is always 18 decimals, so divide by the decimals of the token
        // to ensure that we always report the value in ETH as 18 decimals
        uint256 divisor = 10 ** IERC20Metadata(token).decimals();

        // We are using the balances directly here which can be manipulated but these values are
        // only used in the strategy where we do additional checks to ensure the pool
        // is a good state
        // slither-disable-next-line reentrancy-benign,reentrancy-no-eth
        return pricer.getPriceInEth(token) * balances[index] / divisor;
    }

    function adjustBaseAprForBalancerYieldProtocolFee(
        uint256 unadjustedBaseApr
    ) internal view returns (uint256) {
        // balancer admin fee is 18 decimals
        // we want to return a value that is the non-balancer amount
        uint256 adminFeeRate = 1e18 - balancerVault.getProtocolFeesCollector().getSwapFeePercentage();
        return unadjustedBaseApr * adminFeeRate / 1e18;
    }

    function getVirtualPrice() internal view virtual returns (uint256 virtualPrice);

    /// @notice for composable pools the pool token is filtered out
    function getPoolTokens() internal view virtual returns (IERC20[] memory tokens, uint256[] memory balances);

    /// @notice Returns true if Balancer does not tax any of the yield bearing tokens
    function _isExemptFromYieldProtocolFee() internal view virtual returns (bool) {
        return false;
    }
}
