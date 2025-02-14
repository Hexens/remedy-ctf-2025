// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Challenge {
    address public immutable PLAYER;

    address constant public LPT    = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;
    address constant public TARGET = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

    constructor (address player) {
        PLAYER = player;
    }

    function claimLPT() external {
        ILPT(LPT).transfer(msg.sender, 5000 ether);
    }

    function isSolved() external view returns (bool) {
        return TARGET.balance == 0;
    }
}

interface ILPT {
    function transfer(address, uint256) external;
}