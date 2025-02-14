// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

library StrategyUtils {
    error CannotConvertUintToInt();

    function convertUintToInt(
        uint256 value
    ) internal pure returns (int256) {
        // slither-disable-next-line timestamp
        if (value > uint256(type(int256).max)) revert CannotConvertUintToInt();
        return int256(value);
    }
}
