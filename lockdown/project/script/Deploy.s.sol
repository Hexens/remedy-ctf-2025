// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-ctf/CTFDeployer.sol";

import "src/Challenge.sol";

contract Deploy is CTFDeployer {
    function deploy(address system, address player) internal override returns (address challenge) {
        vm.startBroadcast(system);

        challenge = address(new Challenge(player));
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).transfer(challenge, 1_000_520e6);
        Challenge(challenge).deploy();

        vm.stopBroadcast();
    }
}
