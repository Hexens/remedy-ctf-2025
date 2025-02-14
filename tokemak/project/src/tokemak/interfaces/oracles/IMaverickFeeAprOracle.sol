// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/// @notice Maverick Boosted Position Fee APR must be computed offchain
interface IMaverickFeeAprOracle {
    /// @notice Save for future use the feeApr for a boosted position and the timestamp for when it was calculated
    /// @param boostedPosition address of a maverick boosted position
    /// @param feeApr feeApr for the boosted position as computed offchain with scale 1e18 = 1% feeApr
    /// @param queriedTimestamp the block.timestamp of the block used in the offchain script to compute feeApr
    function setFeeApr(address boostedPosition, uint256 feeApr, uint256 queriedTimestamp) external;

    /// @notice get the latest feeApr of a boosted position. Will revert if the fee apr was not set or is expired
    /// @param boostedPosition the boosted position address to get the feeApr for
    function getFeeApr(
        address boostedPosition
    ) external view returns (uint256 feeApr);

    /// @notice Change the latency that is the oldest a feeApr queriedTimestamp can be before reverted
    /// @param _maxFeeAprLatency max time in seconds since a feeApr has been calculated before getFeeApr() reverts
    function setMaxFeeAprLatency(
        uint256 _maxFeeAprLatency
    ) external;
}
