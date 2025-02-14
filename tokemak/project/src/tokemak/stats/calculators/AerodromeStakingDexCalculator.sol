// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IPool } from "src/tokemak/interfaces/external/aerodrome/IPool.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Stats } from "src/tokemak/stats/Stats.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AerodromeStakingDexCalculator is IDexLSTStats, BaseStatsCalculator {
    address public poolAddress;
    address[2] public reserveTokens;
    uint256[2] public reserveTokensDecimals;
    ILSTStats[2] public lstStats;
    bytes32 internal _aprId;

    struct InitData {
        address poolAddress;
    }

    error ShouldNotSnapshot();
    error DependentAprIdsNotLength2();

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseStatsCalculator(_systemRegistry) { }

    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) external override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));
        Errors.verifyNotZero(decodedInitData.poolAddress, "poolAddress");
        poolAddress = decodedInitData.poolAddress;

        reserveTokens[0] = IPool(poolAddress).token0();
        reserveTokens[1] = IPool(poolAddress).token1();

        IStatsCalculatorRegistry registry = systemRegistry.statsCalculatorRegistry();

        _aprId = keccak256(abi.encode("aerodromeSVAmm", decodedInitData.poolAddress));

        if (dependentAprIds.length != 2) {
            revert DependentAprIdsNotLength2();
        }

        for (uint256 i = 0; i < 2; i++) {
            bytes32 dependentAprId = dependentAprIds[i];
            address coin = reserveTokens[i];
            Errors.verifyNotZero(coin, "coin");
            reserveTokensDecimals[i] = IERC20Metadata(coin).decimals();

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
    function getAddressId() external view returns (address) {
        return poolAddress;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IStatsCalculator
    /// @dev This calculator does not need to track any information over time so it does not need to snapshot.
    function shouldSnapshot() public pure override returns (bool) {
        return false;
    }

    /// @inheritdoc BaseStatsCalculator
    /// @dev This calculator does not need to record anything so if it ever calls _snapshot() something went wrong.
    function _snapshot() internal pure override {
        revert ShouldNotSnapshot();
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

        uint256[] memory reserveAmounts = new uint256[](2);

        reserveAmounts[0] = IPool(poolAddress).reserve0();
        reserveAmounts[1] = IPool(poolAddress).reserve1();

        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        uint256[] memory reservesInEthMemory = new uint256[](2);

        reservesInEthMemory[0] =
            (reserveAmounts[0] * pricer.getPriceInEth(reserveTokens[0])) / (10 ** reserveTokensDecimals[0]);

        reservesInEthMemory[1] =
            (reserveAmounts[1] * pricer.getPriceInEth(reserveTokens[1])) / (10 ** reserveTokensDecimals[1]);

        //slither-disable-next-line uninitialized-local
        StakingIncentiveStats memory stakingIncentiveStats;

        return DexLSTStatsData({
            lastSnapshotTimestamp: block.timestamp,
            feeApr: 0, // When staking LP on Aerodrome for AERO emissions LPs cannot earn swap fees
            lstStatsData: lstStatsData,
            reservesInEth: reservesInEthMemory,
            stakingIncentiveStats: stakingIncentiveStats
        });
    }
}
