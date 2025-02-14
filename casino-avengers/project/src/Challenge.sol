// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Casino} from "./Casino.sol";

contract Challenge {
    address public immutable PLAYER;
    Casino public immutable CASINO;

    constructor(address player) {
        PLAYER = player;
        CASINO = new Casino(msg.sender);
    }

    function isSolved() external view returns (bool) {
        return address(PLAYER).balance >= 99 ether
            && address(CASINO).balance == 0;
    }
}