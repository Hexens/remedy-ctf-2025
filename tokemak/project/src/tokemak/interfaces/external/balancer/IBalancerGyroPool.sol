// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Interface for ECLP and 2CLP pools
interface IBalancerGyroPool {
    /// @notice Virtual Price equivalent for Gyro Pools
    function getInvariantDivActualSupply() external view returns (uint256);

    /// @notice Returns price of token0 in terms of token1
    function getPrice() external view returns (uint256);

    /**
     * @notice Effective BPT supply.
     *
     *  This is the same as `totalSupply()` but also accounts for the fact that the pool owes
     *  protocol fees to the pool in the form of unminted LP shares created on the next join/exit,
     *  diluting LPers. Thus, this is the totalSupply() that the next join/exit operation will see.
     */
    function getActualSupply() external view returns (uint256);
}
