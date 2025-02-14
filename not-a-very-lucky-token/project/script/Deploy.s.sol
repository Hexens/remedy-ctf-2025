// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-ctf/CTFDeployer.sol";

import {Challenge} from "src/Challenge.sol";

contract Deploy is CTFDeployer {
    function deploy(address system, address player) internal override returns (address challenge) {
        vm.startBroadcast(system);

        challenge = address(new Challenge{value: 10 ether}(player));

        vm.stopBroadcast();
    }
}
