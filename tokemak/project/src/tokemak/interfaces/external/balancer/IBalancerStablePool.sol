// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @dev This interface is being used for v2 and v3, as both a constant signature for this function
interface IBalancerStablePool {
    /// @notice Used to get amplification for stable pool
    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision);
}
