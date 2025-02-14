// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface ILRTConfig {
    /// @notice Gets a contract by a bytes32 contractId
    /// @param contractId bytes32 key identifying a contract stored in the config
    function getContract(
        bytes32 contractId
    ) external view returns (address);
}
