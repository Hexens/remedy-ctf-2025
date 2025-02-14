// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAuraStashToken {
    /// @notice Returns whether the stash token is valid
    function isValid() external view returns (bool);

    /// @notice Returns actual reward token
    function baseToken() external view returns (address);
}
