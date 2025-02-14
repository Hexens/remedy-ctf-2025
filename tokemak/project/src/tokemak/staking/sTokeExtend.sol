// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccTokeV1 } from "src/tokemak/interfaces/staking/IAccTokeV1.sol";

contract StokeExtend {
    using SafeERC20 for IERC20;

    uint256 public constant DEPOSIT_AMT = 1;

    uint256 public constant COOL_DOWN = 2 days;

    IAccTokeV1 public immutable acc;

    IERC20 public immutable toke;

    mapping(address => uint256) public lastUsed;

    error TooSoon();
    error InvalidDuration();
    error InvalidUser();

    constructor(address accV1, address _toke) {
        acc = IAccTokeV1(accV1);
        toke = IERC20(_toke);
        toke.safeApprove(accV1, 1e18);
    }

    /// @notice Extend your sTOKE lock by depositing a small amount of TOKE (on the house)
    /// @dev Users can use 1 wei of free TOKE to extend every 2 days
    /// @param newDuration Cycles you wish to be deposited for
    function extend(
        uint256 newDuration
    ) external {
        // slither-disable-next-line timestamp
        if (lastUsed[msg.sender] + COOL_DOWN > block.timestamp) {
            revert TooSoon();
        }
        lastUsed[msg.sender] = block.timestamp;

        // slither-disable-next-line unused-return
        (, uint256 lockDuration, uint256 amount) = acc.getDepositInfo(msg.sender);
        if (newDuration <= lockDuration) {
            revert InvalidDuration();
        }
        if (amount == 0) {
            revert InvalidUser();
        }

        acc.lockTokeFor(DEPOSIT_AMT, newDuration, msg.sender);
    }
}
