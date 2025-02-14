// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// reference: https://docs.convexfinance.com/convexfinanceintegration/cvx-minting
library ConvexRewards {
    uint256 internal constant CVX_MAX_SUPPLY = 100_000_000 * 1e18; // 100 mil max supply
    uint256 internal constant CLIFF_COUNT = 1000;
    uint256 internal constant CLIFF_SIZE = CVX_MAX_SUPPLY / CLIFF_COUNT; // 100_000 per clif

    /**
     * @notice Calculates the amount of CVX that is minted given the amount of CRV earned
     * @param cvxToken address for CVX token
     * @param crvEarned the amount of CRV reward that was earned
     */
    function getCVXMintAmount(address cvxToken, uint256 crvEarned) internal view returns (uint256) {
        uint256 cvxSupply = IERC20(cvxToken).totalSupply();

        // if no cvx has been minted, pre-mine the same amount as the provided crv
        if (cvxSupply == 0 || crvEarned == 0) return 0;

        // determine the current cliff
        uint256 currentCliff = cvxSupply / CLIFF_SIZE;

        // if the current cliff is below the max, then CVX will be minted
        if (currentCliff < CLIFF_COUNT) {
            uint256 remainingCliffs = CLIFF_COUNT - currentCliff;
            uint256 cvxEarned = crvEarned * remainingCliffs / CLIFF_COUNT;

            // ensure that the max supply has not been exceeded
            uint256 amountUntilMax = CVX_MAX_SUPPLY - cvxSupply;
            if (cvxEarned > amountUntilMax) {
                // if maxSupply would be exceeded then return the remaining supply
                return amountUntilMax;
            }

            return cvxEarned;
        }

        return 0;
    }
}
