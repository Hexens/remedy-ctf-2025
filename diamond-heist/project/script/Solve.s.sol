// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Script.sol";

import "script/exploit/Exploit.sol";
import "script/exploit/Exploit2.sol";

contract Solve1 is Script {
    function run() external {
        vm.startBroadcast(/* private key */);

        Challenge challenge = Challenge(/* challenge contract */);
        Exploit exploit = new Exploit(challenge);
        exploit.exploit();

        vm.stopBroadcast();
    }
}

contract Solve2 is Script {
    function run() external {
        vm.startBroadcast(/* private key */);

        Challenge challenge = Challenge(/* challenge contract */);
        Exploit2 exploit = new Exploit2(challenge);
        exploit.exploit();

        vm.stopBroadcast();
    }
}