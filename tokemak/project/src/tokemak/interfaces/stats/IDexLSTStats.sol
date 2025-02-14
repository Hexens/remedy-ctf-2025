// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";

/// @title Return stats DEXs with LSTs
interface IDexLSTStats {
    event DexSnapshotTaken(uint256 snapshotTimestamp, uint256 priorFeeApr, uint256 newFeeApr, uint256 unfilteredFeeApr);

    struct StakingIncentiveStats {
        // time-weighted average total supply to prevent spikes/attacks from impacting rebalancing
        uint256 safeTotalSupply;
        // rewardTokens, annualizedRewardAmounts, and periodFinishForRewards will match indexes
        // they are split to workaround an issue with forge having nested structs
        // address of the reward tokens
        address[] rewardTokens;
        // the annualized reward rate for the reward token
        uint256[] annualizedRewardAmounts;
        // the timestamp for when the rewards are set to terminate
        uint40[] periodFinishForRewards;
        // incentive rewards score. max 48, min 0
        uint8 incentiveCredits;
    }

    struct DexLSTStatsData {
        uint256 lastSnapshotTimestamp;
        uint256 feeApr;
        uint256[] reservesInEth;
        StakingIncentiveStats stakingIncentiveStats;
        ILSTStats.LSTStatsData[] lstStatsData;
    }

    /// @notice Get the current stats for the DEX with underlying LST tokens
    /// @dev Returned data is a combination of current data and filtered snapshots
    /// @return dexLSTStatsData current data on the DEX
    function current() external returns (DexLSTStatsData memory dexLSTStatsData);
}
