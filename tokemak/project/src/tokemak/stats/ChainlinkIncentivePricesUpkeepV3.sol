// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { Ownable2Step } from "src/tokemak/access/Ownable2Step.sol";
import { IncentivePricingStats } from "src/tokemak/stats/calculators/IncentivePricingStats.sol";

contract ChainlinkIncentivePricesUpkeepV3 is Ownable2Step {
    uint256 public maxPerCheck = 20;

    function checkUpkeep(
        bytes calldata checkData
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        IncentivePricingStats incentivePricing = IncentivePricingStats(abi.decode(checkData, (address)));
        (address[] memory tokenAddresses, IncentivePricingStats.TokenSnapshotInfo[] memory infos) =
            incentivePricing.getTokenPricingInfo();
        uint256 tokenLen = tokenAddresses.length;
        address[] memory todo = new address[](tokenLen);
        uint256 interval = incentivePricing.MIN_INTERVAL();

        uint256 todoCnt = 0;
        for (uint256 i = 0; i < tokenLen; ++i) {
            IncentivePricingStats.TokenSnapshotInfo memory info = infos[i];

            // slither-disable-next-line timestamp
            if (info.lastSnapshot + interval < block.timestamp) {
                todo[todoCnt++] = tokenAddresses[i];
            }
        }

        uint256 actualLen = todoCnt > maxPerCheck ? maxPerCheck : todoCnt;
        address[] memory trimmed = new address[](actualLen);
        uint256 ix = 0;
        for (uint256 i = 0; i < tokenLen; ++i) {
            if (todo[i] != address(0)) {
                trimmed[ix++] = todo[i];
            }
        }
        upkeepNeeded = actualLen > 0;
        performData = abi.encode(address(incentivePricing), trimmed);
    }

    function performUpkeep(
        bytes calldata performData
    ) external {
        (address incentivePricingAddr, address[] memory tokens) = abi.decode(performData, (address, address[]));
        IncentivePricingStats incentivePricing = IncentivePricingStats(incentivePricingAddr);
        incentivePricing.snapshot(tokens);
    }

    function setMaxPerCheck(
        uint256 newValue
    ) external onlyOwner {
        Errors.verifyNotZero(newValue, "newValue");

        // slither-disable-next-line events-maths
        maxPerCheck = newValue;
    }
}
