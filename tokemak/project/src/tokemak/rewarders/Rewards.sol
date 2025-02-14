// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IRewards } from "src/tokemak/interfaces/rewarders/IRewards.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { EIP712, ECDSA } from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

contract Rewards is IRewards, SecurityBase, SystemComponent, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    mapping(address => uint256) public override claimedAmounts;

    bytes32 private constant _RECIPIENT_TYPEHASH =
        keccak256("Recipient(uint256 chainId,uint256 cycle,address wallet,uint256 amount)");

    IERC20 public immutable override vaultToken;
    address public override rewardsSigner;

    constructor(
        ISystemRegistry _systemRegistry,
        IERC20 _vaultToken,
        address _rewardsSigner
    )
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
        EIP712("Vault Token Distribution", "1")
    {
        Errors.verifyNotZero(address(_vaultToken), "token");
        Errors.verifyNotZero(address(_rewardsSigner), "signerAddress");

        // slither-disable-next-line missing-zero-check
        vaultToken = _vaultToken;
        // slither-disable-next-line missing-zero-check
        rewardsSigner = _rewardsSigner;
    }

    function _hashRecipient(
        Recipient memory recipient
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(_RECIPIENT_TYPEHASH, recipient.chainId, recipient.cycle, recipient.wallet, recipient.amount)
        );
    }

    /// @inheritdoc IRewards
    function genHash(
        Recipient memory recipient
    ) public view returns (bytes32) {
        return _hashTypedDataV4(_hashRecipient(recipient));
    }

    function _getChainID() private view returns (uint256) {
        return block.chainid;
    }

    /// @inheritdoc IRewards
    function setSigner(
        address newSigner
    ) external override onlyOwner {
        Errors.verifyNotZero(newSigner, "newSigner");

        // slither-disable-next-line missing-zero-check
        rewardsSigner = newSigner;

        emit SignerSet(newSigner);
    }

    /// @inheritdoc IRewards
    function getClaimableAmount(
        Recipient calldata recipient
    ) external view override returns (uint256) {
        return recipient.amount - claimedAmounts[recipient.wallet];
    }

    /// @inheritdoc IRewards
    function claim(Recipient calldata recipient, uint8 v, bytes32 r, bytes32 s) external override returns (uint256) {
        if (recipient.wallet != msg.sender) {
            revert Errors.SenderMismatch(recipient.wallet, msg.sender);
        }

        return _claim(recipient, v, r, s, msg.sender);
    }

    /// @inheritdoc IRewards
    function claimFor(
        Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256) {
        if (msg.sender != address(systemRegistry.autoPoolRouter())) {
            revert Errors.AccessDenied();
        }

        return _claim(recipient, v, r, s, recipient.wallet);
    }

    // @dev bytes32 s is bytes calldata signature
    function _claim(
        Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address sendTo
    ) internal returns (uint256) {
        address signatureSigner = genHash(recipient).recover(v, r, s);

        if (signatureSigner != rewardsSigner) {
            revert Errors.InvalidSigner(signatureSigner);
        }

        if (recipient.chainId != _getChainID()) {
            revert Errors.InvalidChainId(recipient.chainId);
        }

        uint256 claimedAmount = claimedAmounts[recipient.wallet];
        uint256 claimableAmount = recipient.amount - claimedAmount;

        if (claimableAmount == 0) {
            revert Errors.ZeroAmount();
        }

        if (claimableAmount > vaultToken.balanceOf(address(this))) {
            revert Errors.InsufficientBalance(address(vaultToken));
        }

        claimedAmounts[recipient.wallet] = claimedAmount + claimableAmount;

        emit Claimed(recipient.cycle, recipient.wallet, claimableAmount);

        vaultToken.safeTransfer(sendTo, claimableAmount);

        return claimableAmount;
    }
}
