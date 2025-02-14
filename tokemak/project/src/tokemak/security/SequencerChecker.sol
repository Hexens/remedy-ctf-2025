// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ISequencerChecker } from "src/tokemak/interfaces/security/ISequencerChecker.sol";
import { IAggregatorV3Interface } from "src/tokemak/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract SequencerChecker is ISequencerChecker, SystemComponent {
    /// @notice Period of time to pass after sequencer comes back up
    uint256 public immutable gracePeriod;

    /// @notice Chainlink feed for sequencer uptime
    IAggregatorV3Interface public immutable sequencerUptimeFeed;

    constructor(
        ISystemRegistry _systemRegistry,
        IAggregatorV3Interface _sequencerUptimeFeed,
        uint256 _gracePeriod
    ) SystemComponent(_systemRegistry) {
        Errors.verifyNotZero(address(_sequencerUptimeFeed), "_sequencerUptimeFeed");
        Errors.verifyNotZero(_gracePeriod, "_gracePeriod");

        sequencerUptimeFeed = _sequencerUptimeFeed;
        gracePeriod = _gracePeriod;
    }

    /// @inheritdoc ISequencerChecker
    function checkSequencerUptimeFeed() external view returns (bool) {
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();

        if (answer > 1 || roundId == 0 || startedAt == 0) {
            revert Errors.InvalidDataReturned();
        }

        // Check answer. If sequencer is up make sure for appropriate amount of time
        // slither-disable-next-line timestamp
        if (answer == 1 || block.timestamp - startedAt < gracePeriod) {
            return false;
        }
        return true;
    }
}
