// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BaseClaimingDestinationVaultExtension } from
    "src/tokemak/vault/extensions/base/BaseClaimingDestinationVaultExtension.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

import { IMerkleDistributor } from "src/tokemak/interfaces/external/kelpdao/IMerkleDistributor.sol";

/// @title Destination vault extension for claiming KelpDao rewards
contract KelpDaoClaimingDestinationVaultExtension is BaseClaimingDestinationVaultExtension {
    address public immutable claimContract;
    IERC20 public immutable claimToken;

    /// @param account Account that can claim rewards
    /// @param cumulativeAmount Cumulative amount of rewards for account. Used in Merkle calculations
    /// @param index The index of the claim
    /// @param merkleProof Merkle proof used in verification of claim
    struct KelpDaoClaimParams {
        address account;
        uint256 cumulativeAmount;
        uint256 index;
        bytes32[] merkleProof;
    }

    // slither-disable-start similar-names
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
    // slither-disable-end similar-names

    /// @inheritdoc BaseClaimingDestinationVaultExtension
    function _claim(
        bytes memory data
    ) internal override returns (uint256[] memory amountsClaimed, address[] memory tokensClaimed) {
        KelpDaoClaimParams memory params = abi.decode(data, (KelpDaoClaimParams));

        // Don't want revert in case of revert in claim contract, catch and let execution move on
        try IMerkleDistributor(claimContract).claim(
            params.index, params.account, params.cumulativeAmount, params.merkleProof
        ) { } catch { }

        amountsClaimed = new uint256[](1);
        tokensClaimed = new address[](1);

        amountsClaimed[0] = claimToken.balanceOf(address(this));
        tokensClaimed[0] = address(claimToken);

        // Should only be calling if we either have a claim or funds existing in DV
        Errors.verifyNotZero(amountsClaimed[0], "amountsClaimed[0]");
    }
}
