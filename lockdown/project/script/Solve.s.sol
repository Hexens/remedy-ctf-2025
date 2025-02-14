// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Script.sol";

import "script/exploit/Exploit.sol";

contract Solve is Script {
    function run() external {
        vm.startBroadcast(/* private key */);

        Challenge challenge = Challenge(/* challenge address */);
        Exploit exploit = new Exploit(challenge);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).transfer(address(exploit), 500e6);
        exploit.exploit();

        vm.stopBroadcast();
    }
}