// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IBasePool {
    /// @notice Returns the pool ID
    function getPoolId() external view returns (bytes32);

    /// @notice Returns the current swap fee percentage as a 18 decimal fixed point number
    /// @return The current swap fee percentage
    function getSwapFeePercentage() external view returns (uint256);

    /// @notice Gets scaling factors for tokens in pool in order
    /// @dev Accounts for rate scaling as well
    /// @return Array of scaling factors, in e18
    function getScalingFactors() external view returns (uint256[] memory);
}
