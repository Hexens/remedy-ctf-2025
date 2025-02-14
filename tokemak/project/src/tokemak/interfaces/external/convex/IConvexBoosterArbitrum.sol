// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice main Convex contract(booster.sol) basic interface
interface IConvexBoosterArbitrum {
    /// @notice deposit into convex, receive a tokenized deposit
    function deposit(uint256 _pid, uint256 _amount) external returns (bool);
}
