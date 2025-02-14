// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";

/**
 * @title IPctFeeSplitter Interface
 * @notice Interface for the PctFeeSplitter contract
 */
interface IPctFeeSplitter is ISystemComponent {
    /// @param pct The percentage of the fee to be distributed to the recipient
    /// @param recipient The address of the recipient of the fee
    struct FeeRecipient {
        uint16 pct;
        address recipient;
    }

    /**
     * @notice set the fee recipients and their respective percentages.
     * @param _feeRecipients The array of FeeRecipient struct.
     * @dev can only be called by the AutoPoolManager and the total percentage should be 100%.
     */
    function setFeeRecipients(
        FeeRecipient[] memory _feeRecipients
    ) external;

    /**
     * @notice Distribute fees among the fee recipients in the denominated token.
     * @param token The fee denominated token to be distributed among recipeints.
     * @dev can only be called by one of the fee recipients.
     */
    function claimFees(
        address token
    ) external;
}
