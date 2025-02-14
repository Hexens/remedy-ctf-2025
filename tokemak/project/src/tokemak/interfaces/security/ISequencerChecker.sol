// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface ISequencerChecker {
    /// @notice Checks Chainlink feed for L2 sequencer status
    /// @return Bool telling whether sequencer is up or not
    function checkSequencerUptimeFeed() external view returns (bool);
}
