// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { IPctFeeSplitter } from "src/tokemak/interfaces/vault/fees/IPctFeeSplitter.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

/// @title PctFeeSplitter contract
contract PctFeeSplitter is IPctFeeSplitter, SecurityBase, SystemComponent {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_PCT = 10_000;

    FeeRecipient[] public feeRecipients;

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc IPctFeeSplitter
    function setFeeRecipients(
        FeeRecipient[] memory _feeRecipients
    ) external hasRole(Roles.AUTO_POOL_MANAGER) {
        uint16 totalPct = 0;
        delete feeRecipients;
        for (uint256 i = 0; i < _feeRecipients.length;) {
            Errors.verifyNotZero(_feeRecipients[i].recipient, "fee-recipient");
            Errors.verifyNotZero(_feeRecipients[i].pct, "fee-pct");

            totalPct += _feeRecipients[i].pct;
            feeRecipients.push(_feeRecipients[i]);

            unchecked {
                ++i;
            }
        }
        if (totalPct != MAX_PCT) {
            revert Errors.InvalidParams();
        }
    }

    /// @inheritdoc IPctFeeSplitter
    function claimFees(
        address token
    ) external {
        bool calledByRecipient = false;
        uint256 length = feeRecipients.length;
        uint256 feeBalance = IERC20(token).balanceOf(address(this));
        for (uint256 i = 0; i < length;) {
            FeeRecipient memory recipient = feeRecipients[i];
            if (recipient.recipient == msg.sender) {
                calledByRecipient = true;
            }
            uint256 amount = feeBalance * recipient.pct / MAX_PCT;

            //Transfer all the left over for the last recipient
            if (i == length - 1) {
                amount = IERC20(token).balanceOf(address(this));
            }

            Errors.verifyNotZero(amount, "fee-amount");

            IERC20(token).safeTransfer(recipient.recipient, amount);

            unchecked {
                ++i;
            }
        }
        if (!calledByRecipient) {
            revert Errors.InvalidSigner(msg.sender);
        }
    }
}
