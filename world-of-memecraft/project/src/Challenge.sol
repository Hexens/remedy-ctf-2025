// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/WorldOfMemecraft.sol";

contract Challenge {
    address public immutable PLAYER;
    WorldOfMemecraft public immutable WORLD_OF_MEMECRAFT;

    constructor(address player) {
        PLAYER = player;
        WORLD_OF_MEMECRAFT = new WorldOfMemecraft();
    }

    function isSolved() external view returns (bool) {
        return !WORLD_OF_MEMECRAFT.getMonster(0).alive;
    }
}