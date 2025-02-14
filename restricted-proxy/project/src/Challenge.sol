// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "src/CTF.sol";

contract Challenge {
    address public immutable PLAYER;
    address public immutable ctf;

    constructor(address player) payable {
        PLAYER = player;
        ctf = address(new CTF{value: 100 ether}());
    }

    function isSolved() external view returns (bool) {
        return PLAYER.balance >= 100 ether
            && ctf.balance == 0 ether;
    }
}