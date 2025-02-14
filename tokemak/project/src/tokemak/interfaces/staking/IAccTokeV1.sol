// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IAccTokeV1 {
    /// @notice Lock Toke for `numOfCycles` cycles -> get accToke
    /// @param tokeAmount Amount of TOKE to lock up
    /// @param numOfCycles Number of cycles to lock for
    function lockToke(uint256 tokeAmount, uint256 numOfCycles) external;

    /// @notice Lock Toke for a different account for `numOfCycles` cycles -> that account gets resulting accTOKE
    /// @param tokeAmount Amount of TOKE to lock up
    /// @param numOfCycles Number of cycles to lock for
    /// @param account Account to lock TOKE for
    function lockTokeFor(uint256 tokeAmount, uint256 numOfCycles, address account) external;

    /// @notice Get all the deposit information for a specified account
    /// @param account Account to get deposit info for
    /// @return lockCycle Cycle Index when deposit was made
    /// @return lockDuration Number of cycles deposit is locked for
    /// @return amount Amount of TOKE deposited
    function getDepositInfo(
        address account
    ) external view returns (uint256 lockCycle, uint256 lockDuration, uint256 amount);

    /// @notice Grants role to user
    function grantRole(bytes32 role, address user) external;
}
