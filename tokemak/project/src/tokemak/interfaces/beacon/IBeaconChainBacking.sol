// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

/**
 * Most LSD tokens report the amount of funds they have staked on the Beacon Chain back to Mainnet periodically.
 * FrxETH does not. This value is needed for various calculations and so we will run a backend service to keep this
 * value up to date. This contract should track this value and the last time it was set.
 */
interface IBeaconChainBacking {
    /**
     * @notice Saves the most recent ratio and it's timestamp into the contract storage
     * @dev Calculates `ratio` with `totalAssets * decimalPad / totalLiabilities` formula
     * @param totalAssets Amount of protocol's funds
     * @param totalLiabilities Amount of protocol's liability funds
     * @param queriedTimestamp Time-point when the value is actual
     */
    function update(uint208 totalAssets, uint208 totalLiabilities, uint48 queriedTimestamp) external;

    /**
     * @notice Returns the most recent ratio and it's timestamp
     * @return ratio Amount of funds staked on the Beacon Chain
     * @return queriedTimestamp Last time the `ratio` was set
     */
    function current() external view returns (uint208 ratio, uint48 queriedTimestamp);
}
