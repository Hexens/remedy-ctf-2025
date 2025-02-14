// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-ctf/CTFDeployer.sol";

import "src/Challenge.sol";

contract Deploy is CTFDeployer {
    address constant LPT = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;

    function deploy(address system, address player) internal override returns (address challenge) {
        vm.startBroadcast(system);

        challenge = address(new Challenge(player));
        ILPT(LPT).transfer(address(challenge), 5000 ether);

        vm.stopBroadcast();
    }
}