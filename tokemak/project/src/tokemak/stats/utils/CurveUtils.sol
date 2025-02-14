// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Stats } from "src/tokemak/stats/Stats.sol";

library CurveUtils {
    function getDecimals(
        address token
    ) internal view returns (uint256) {
        if (token == Stats.CURVE_ETH) {
            return 18;
        } else {
            return IERC20Metadata(token).decimals();
        }
    }
}
