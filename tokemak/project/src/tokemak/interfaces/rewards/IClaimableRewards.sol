// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IClaimableRewards {
    error ClaimRewardsFailed();
    error TokenAddressZero();

    event RewardsClaimed(IERC20[], uint256[]);
}
