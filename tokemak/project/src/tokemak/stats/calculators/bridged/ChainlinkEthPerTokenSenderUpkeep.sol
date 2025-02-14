// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { EthPerTokenSender } from "src/tokemak/stats/calculators/bridged/EthPerTokenSender.sol";

contract ChainlinkEthPerTokenSenderUpkeep {
    /// =====================================================
    /// Errors
    /// =====================================================

    error NoAddresses();

    /// =====================================================
    /// Functions - External
    /// =====================================================

    function performUpkeep(
        bytes calldata performData
    ) external {
        (address senderAddr, address[] memory addrs) = abi.decode(performData, (address, address[]));
        if (addrs.length > 0) {
            EthPerTokenSender(senderAddr).execute(addrs);
        } else {
            revert NoAddresses();
        }
    }

    function checkUpkeep(
        bytes calldata checkData
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        EthPerTokenSender sender = EthPerTokenSender(abi.decode(checkData, (address)));
        address[] memory sendFor = sender.shouldSend(0, type(uint256).max);

        return (sendFor.length > 0, abi.encode(sender, sendFor));
    }
}
