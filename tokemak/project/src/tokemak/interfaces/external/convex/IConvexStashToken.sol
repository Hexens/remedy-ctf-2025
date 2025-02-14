// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IConvexStashToken {
    /// @notice Returns actual reward token
    function token() external view returns (address);

    /// @notice Returns whether the current stash token is invalid
    function isInvalid() external view returns (bool);

    /// @notice Returns current balance of the given wallet
    /// @param wallet address to balance for
    function balanceOf(
        address wallet
    ) external view returns (uint256);
}
