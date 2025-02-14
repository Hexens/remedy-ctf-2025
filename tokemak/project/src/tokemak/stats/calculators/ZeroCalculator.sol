// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable var-name-mixedcase

import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { Ownable2Step } from "src/tokemak/access/Ownable2Step.sol";

contract ZeroCalculator is Ownable2Step, IDexLSTStats {
    address public lpToken;

    address public pool;

    constructor() { }

    /// @notice Returns an empty struct, all values default or zero
    function current() external view override returns (DexLSTStatsData memory dexLSTStatsData) {
        dexLSTStatsData.lastSnapshotTimestamp = block.timestamp;
    }

    // @notice Set so the calculator can pass validation when its configured on Destination
    function setLpTokenPool(address _lpToken, address _pool) external onlyOwner {
        // slither-disable-next-line missing-zero-check
        lpToken = _lpToken;

        // slither-disable-next-line missing-zero-check
        pool = _pool;
    }
}
