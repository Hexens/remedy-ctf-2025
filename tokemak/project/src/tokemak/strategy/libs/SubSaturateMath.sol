// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

library SubSaturateMath {
    function subSaturate(uint256 self, uint256 other) internal pure returns (uint256) {
        if (other >= self) return 0;
        return self - other;
    }

    function subSaturate(int256 self, int256 other) internal pure returns (int256) {
        if (other >= self) return 0;
        return self - other;
    }
}
