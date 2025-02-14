// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IMerkleDistributor {
    /// @dev claim the given amount of the token to the given address. Reverts if the inputs are invalid
    /// @param index The index of the claim
    /// @param account The address to send the token to
    /// @param cumulativeAmount The cumulative amount of the claim
    /// @param merkleProof The merkle proof to verify the claim
    function claim(uint256 index, address account, uint256 cumulativeAmount, bytes32[] calldata merkleProof) external;
}
