// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface ISystemSecurity {
    /// @notice Get the number of NAV/share operations currently in progress
    /// @return Number of operations
    function navOpsInProgress() external view returns (uint256);

    /// @notice Called at the start of any NAV/share changing operation
    function enterNavOperation() external;

    /// @notice Called at the end of any NAV/share changing operation
    function exitNavOperation() external;

    /// @notice Whether or not the system as a whole is paused
    function isSystemPaused() external returns (bool);

    /// @notice Sets an autopool in transient storage , this is used to guard against malicious user payloads
    /// that could be used to reenter the system
    /// @param autopool The address of the autopool to set
    /// @dev This is used in the AutopilotRouter to guard against reentrancy via malicious payload in the
    /// swap routes when redeeming
    function setAllowedAutopool(
        address autopool
    ) external;

    /// @notice Clears the autopool from transient storage
    function clearAllowedAutopool() external;
}
