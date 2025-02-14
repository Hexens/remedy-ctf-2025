// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IWorldOfMemecraft {
    struct World {
        string servername;
        uint numPlayers;
        Character[] characters;
        Monster[] monsters;
        mapping(uint256 => address) characterOwner;
        mapping(address => uint256) lastActionBlock;
    }

    struct Character {
        uint256 id;
        uint256 level;
        uint256 health;
        uint256 xp;
    }

    struct Monster {
        uint256 id;
        string name;
        uint256 level;
        uint256 health;
        uint256 kills;
        uint256 xpDrop;
        bool alive;
    }
}
