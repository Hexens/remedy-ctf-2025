// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Script.sol";

import "script/exploit/Exploit.sol";

contract Solve is Script {
    function run() external {
        vm.startBroadcast(/* private key */);

        Challenge challenge = Challenge(/* challenge address */);
        Exploit exploit = new Exploit(challenge);
        exploit.exploit{value: 1 ether}();

        vm.stopBroadcast();
    }
}