// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { ConvexStaking } from "src/tokemak/destinations/adapters/staking/ConvexAdapter.sol";
import { IConvexBooster } from "src/tokemak/interfaces/external/convex/IConvexBooster.sol";

/**
 * @title AuraAdapter
 * @dev This contract implements an adapter for interacting with Aura's reward system.
 * We're using a Convex Adapter as Aura uses the Convex interfaces for LPs staking.
 */
library AuraStaking {
    /**
     * @notice Deposits and stakes Curve LP tokens to Convex
     * @dev Calls to external contract
     * @param booster Convex Booster address
     * @param lpToken Curve LP token to deposit
     * @param staking Convex reward contract associated with the Curve LP token
     * @param poolId Convex poolId for the associated Curve LP token
     * @param amount Quantity of Curve LP token to deposit and stake
     */
    function depositAndStake(
        IConvexBooster booster,
        address lpToken,
        address staking,
        uint256 poolId,
        uint256 amount
    ) public {
        ConvexStaking.depositAndStake(booster, lpToken, staking, poolId, amount);
    }

    /**
     * @notice Withdraws a Curve LP token from Convex
     * @dev Does not claim available rewards
     * @dev Calls to external contract
     * @param lpToken Curve LP token to withdraw
     * @param staking Convex reward contract associated with the Curve LP token
     * @param amount Quantity of Curve LP token to withdraw
     */
    function withdrawStake(address lpToken, address staking, uint256 amount) public {
        ConvexStaking.withdrawStake(lpToken, staking, amount);
    }
}
