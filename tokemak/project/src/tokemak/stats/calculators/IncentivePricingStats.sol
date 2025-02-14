// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Stats } from "src/tokemak/stats/Stats.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { IIncentivesPricingStats } from "src/tokemak/interfaces/stats/IIncentivesPricingStats.sol";

/// @notice Calculates EWMA prices for incentives tokens
contract IncentivePricingStats is IIncentivesPricingStats, SystemComponent, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice MIN_INTERVAL is the minimum amount of time (seconds) before a new snapshot is taken
    uint256 public constant MIN_INTERVAL = 8 * 60 * 60; // 8 hours

    /// @notice INIT_SAMPLE_COUNT is the number of samples required to complete initialization, samples are averaged to
    /// initialize the filtered values
    uint256 public constant INIT_SAMPLE_COUNT = 18;

    /// @return FAST_ALPHA the alpha for the fast updating filtered price
    uint256 public constant FAST_ALPHA = 33e16; // 0.33

    /// @return SLOW_ALPHA the alpha for the slow updating filtered price
    uint256 public constant SLOW_ALPHA = 645e14; // 0.0645

    EnumerableSet.AddressSet private registeredTokens;

    // incentive token address => pricing information
    mapping(address => TokenSnapshotInfo) private tokenSnapshotInfo;

    modifier onlyStatsSnapshot() {
        if (!_hasRole(Roles.STATS_SNAPSHOT_EXECUTOR, msg.sender)) {
            revert Errors.MissingRole(Roles.STATS_SNAPSHOT_EXECUTOR, msg.sender);
        }
        _;
    }

    modifier onlyUpdater() {
        if (!_hasRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, msg.sender)) {
            revert Errors.MissingRole(Roles.STATS_INCENTIVE_TOKEN_UPDATER, msg.sender);
        }
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc IIncentivesPricingStats
    function setRegisteredToken(
        address token
    ) external onlyUpdater {
        if (!registeredTokens.add(token)) revert TokenAlreadyRegistered(token);

        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        // if the token isn't registered with the pricing oracle this will fail which is the desired outcome
        updatePricingInfo(pricer, token);

        // pricer handles reentrancy issues
        // slither-disable-next-line reentrancy-events
        emit TokenAdded(token);
    }

    /// @inheritdoc IIncentivesPricingStats
    function removeRegisteredToken(
        address token
    ) external onlyUpdater {
        if (!registeredTokens.remove(token)) revert TokenNotFound(token);
        delete tokenSnapshotInfo[token];
        emit TokenRemoved(token);
    }

    /// @inheritdoc IIncentivesPricingStats
    function getRegisteredTokens() external view returns (address[] memory tokens) {
        return registeredTokens.values();
    }

    /// @inheritdoc IIncentivesPricingStats
    function getTokenPricingInfo()
        external
        view
        returns (address[] memory tokenAddresses, TokenSnapshotInfo[] memory info)
    {
        tokenAddresses = registeredTokens.values();
        uint256 numTokens = registeredTokens.length();
        info = new TokenSnapshotInfo[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            address token = registeredTokens.at(i);
            info[i] = tokenSnapshotInfo[token];
        }
    }

    /// @inheritdoc IIncentivesPricingStats
    function snapshot(
        address[] calldata tokensToSnapshot
    ) external onlyStatsSnapshot {
        if (tokensToSnapshot.length == 0) revert Errors.InvalidParam("tokensToSnapshot");
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        uint256 numTokens = tokensToSnapshot.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            address token = tokensToSnapshot[i];
            Errors.verifyNotZero(token, "token");
            if (!registeredTokens.contains(token)) {
                revert TokenNotFound(token);
            }
            updatePricingInfo(pricer, token);
        }
    }

    /// @inheritdoc IIncentivesPricingStats
    function getPrice(address token, uint40 staleCheck) public view returns (uint256 fastPrice, uint256 slowPrice) {
        if (!registeredTokens.contains(token)) revert TokenNotFound(token);

        TokenSnapshotInfo memory info = tokenSnapshotInfo[token];

        // slither-disable-next-line timestamp
        if (block.timestamp - info.lastSnapshot > staleCheck) revert IncentiveTokenPriceStale(token);

        return (info.fastFilterPrice, info.slowFilterPrice);
    }

    /// @inheritdoc IIncentivesPricingStats
    function getPriceOrZero(
        address token,
        uint40 staleCheck
    ) external view returns (uint256 fastPrice, uint256 slowPrice) {
        if (!registeredTokens.contains(token)) {
            return (0, 0);
        }

        return getPrice(token, staleCheck);
    }

    function updatePricingInfo(IRootPriceOracle pricer, address token) internal {
        // tokenPricing info can be in 3 possible phases
        // 1) initialize phase, just want to accumulate the price to calculate an average
        // 2) exactly met the number of samples for init, update fast/slow filters with the average price
        // 3) post-init, only update the filter values
        TokenSnapshotInfo storage existing = tokenSnapshotInfo[token];

        // slither-disable-next-line timestamp
        if (existing.lastSnapshot + MIN_INTERVAL > block.timestamp) revert TokenSnapshotNotReady(token);

        // pricer handles reentrancy issues
        // slither-disable-next-line reentrancy-no-eth
        uint256 price = pricer.getPriceInEth(token);

        // update the timestamp no matter what phase we're in
        existing.lastSnapshot = uint40(block.timestamp);

        if (existing._initComplete) {
            // post-init phase, just update the filter values
            existing.slowFilterPrice = Stats.getFilteredValue(SLOW_ALPHA, existing.slowFilterPrice, price);
            existing.fastFilterPrice = Stats.getFilteredValue(FAST_ALPHA, existing.fastFilterPrice, price);
        } else {
            // still the initialization phase
            existing._initCount += 1;
            existing._initAcc += price;

            // snapshot count is tracked internally and cannot be manipulated
            // slither-disable-next-line incorrect-equality
            if (existing._initCount == INIT_SAMPLE_COUNT) {
                // if this sample hits the target number, then complete initialize and set the filters
                existing._initComplete = true;
                uint256 averagePrice = existing._initAcc / INIT_SAMPLE_COUNT;
                existing.fastFilterPrice = averagePrice;
                existing.slowFilterPrice = averagePrice;
            }
        }

        emitSnapshotTaken(token, existing);
    }

    function emitSnapshotTaken(address token, TokenSnapshotInfo memory info) internal {
        // pricer handles reentrancy issues
        // slither-disable-next-line reentrancy-events
        emit TokenSnapshot(
            token, info.lastSnapshot, info.fastFilterPrice, info.slowFilterPrice, info._initCount, info._initComplete
        );
    }
}
