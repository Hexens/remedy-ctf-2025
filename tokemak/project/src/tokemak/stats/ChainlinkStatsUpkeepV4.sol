// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { Ownable2Step } from "src/tokemak/access/Ownable2Step.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";

contract ChainlinkStatsUpkeepV4 is Ownable2Step {
    uint256 public maxPerCheck = 10;

    function checkUpkeep(
        bytes calldata checkData
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        ISystemRegistry systemRegistry = ISystemRegistry(abi.decode(checkData, (address)));
        IStatsCalculatorRegistry statsCalcRegistry = systemRegistry.statsCalculatorRegistry();
        // slither-disable-next-line unused-return
        (, address[] memory addresses) = statsCalcRegistry.listCalculators();
        uint256 len = addresses.length;

        address[] memory found = new address[](len);
        uint256 count = 0;

        for (uint256 i = 0; i < len; ++i) {
            IStatsCalculator calc = IStatsCalculator(addresses[i]);

            try calc.shouldSnapshot() returns (bool shouldSnapshot) {
                if (shouldSnapshot) {
                    ++count;
                    found[i] = address(addresses[i]);
                }
            } catch { }
        }

        uint256 actualLen = count > maxPerCheck ? maxPerCheck : count;
        address[] memory trimmed = new address[](actualLen);
        uint256 ix = 0;
        for (uint256 i = 0; i < len && ix < actualLen; ++i) {
            if (found[i] != address(0)) {
                trimmed[ix] = found[i];
                ++ix;
            }
        }
        upkeepNeeded = actualLen > 0;
        performData = abi.encode(trimmed);
    }

    function performUpkeep(
        bytes calldata performData
    ) external {
        (address[] memory addrs) = abi.decode(performData, (address[]));
        for (uint256 i = 0; i < addrs.length;) {
            IStatsCalculator calc = IStatsCalculator(addrs[i]);
            calc.snapshot();

            unchecked {
                ++i;
            }
        }
    }

    function setMaxPerCheck(
        uint256 newValue
    ) external onlyOwner {
        Errors.verifyNotZero(newValue, "newValue");

        // slither-disable-next-line events-maths
        maxPerCheck = newValue;
    }
}
