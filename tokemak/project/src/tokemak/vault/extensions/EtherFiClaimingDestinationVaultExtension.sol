// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BaseClaimingDestinationVaultExtension } from
    "src/tokemak/vault/extensions/base/BaseClaimingDestinationVaultExtension.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

import { ICumulativeMerkleDrop } from "src/tokemak/interfaces/external/etherfi/ICumulativeMerkleDrop.sol";

/// @title Destination vault extension for claiming EtherFi rewards
contract EtherFiClaimingDestinationVaultExtension is BaseClaimingDestinationVaultExtension {
    address public immutable claimContract;
    IERC20 public immutable claimToken;

    /// @param account The account that haas accrued rewards. DV in this context
    /// @param cumulativeAmount Total amount of rewards accrued. Used in Merkle verifications
    /// @param expectedMerkleRoot The expected merkle root for this claim period
    /// @param merkleProof Merkle proof, used for verification of claim
    struct EtherFiClaimParams {
        address account;
        uint256 cumulativeAmount;
        bytes32 expectedMerkleRoot;
        bytes32[] merkleProof;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        address _asyncSwapper,
        address _claimContract,
        address _claimToken
    ) BaseClaimingDestinationVaultExtension(_systemRegistry, _asyncSwapper) {
        Errors.verifyNotZero(_claimContract, "_claimContract");
        Errors.verifyNotZero(_claimToken, "_claimToken");

        // slither-disable-next-line missing-zero-check
        claimContract = _claimContract;
        claimToken = IERC20(_claimToken);
    }

    /// @inheritdoc BaseClaimingDestinationVaultExtension
    function _claim(
        bytes memory data
    ) internal override returns (uint256[] memory amountsClaimed, address[] memory tokensClaimed) {
        EtherFiClaimParams memory params = abi.decode(data, (EtherFiClaimParams));

        // Don't want revert in case of revert in claim contract, catch and let execution move on
        try ICumulativeMerkleDrop(claimContract).claim(
            params.account, params.cumulativeAmount, params.expectedMerkleRoot, params.merkleProof
        ) { } catch { }

        amountsClaimed = new uint256[](1);
        tokensClaimed = new address[](1);

        amountsClaimed[0] = claimToken.balanceOf(address(this));
        tokensClaimed[0] = address(claimToken);

        // Should only be calling if we either have a claim or funds existing in DV
        Errors.verifyNotZero(amountsClaimed[0], "amountsClaimed[0]");
    }
}
