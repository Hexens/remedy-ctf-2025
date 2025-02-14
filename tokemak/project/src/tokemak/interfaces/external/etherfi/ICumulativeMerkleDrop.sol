// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICumulativeMerkleDrop {
    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid
    function claim(
        address account,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external;
}
