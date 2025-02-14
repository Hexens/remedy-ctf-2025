// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/// @title Return stats on base LSTs
interface ILSTStats {
    struct LSTStatsData {
        uint256 lastSnapshotTimestamp;
        uint256 baseApr;
        int256 discount; // positive number is a discount, negative is a premium
        uint24[10] discountHistory; // 7 decimal precision
        uint40 discountTimestampByPercent; // timestamp that the token reached 1pct discount
    }

    /// @notice Get the current stats for the LST
    /// @dev Returned data is a combination of current data and filtered snapshots
    /// @return lstStatsData current data on the LST
    function current() external returns (LSTStatsData memory lstStatsData);

    /// @notice Get the EthPerToken (or Share) for the LST
    /// @return ethPerShare the backing eth for the LST
    function calculateEthPerToken() external view returns (uint256 ethPerShare);

    /// @notice Returns whether to use the market price when calculating discount
    /// @dev Will be true for rebasing tokens and other non-standard tokens
    function usePriceAsDiscount() external view returns (bool useAsDiscount);
}
