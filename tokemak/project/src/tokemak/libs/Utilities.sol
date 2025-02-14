// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

library Utilities {
    /**
     * @notice Gets a subtraction factor based on decimals size.
     * @dev We're making this factor dynamic based on the decimals of the token.
     * @return one unit in scaled down terms, one unit to pad back out
     */
    function getScaleDownFactor(
        uint8 decimals
    ) internal pure returns (uint256, uint256) {
        if (decimals >= 18) {
            return (10 ** (decimals - 3), 1e3);
        }
        if (decimals >= 6) {
            return (10 ** (decimals - 2), 1e2);
        }
        if (decimals >= 2) {
            return (10 ** (decimals - 1), 1e1);
        }
        return (10 ** decimals, 1);
    }
}
