
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWorldOfMemecraft} from "src/interfaces/IWorldOfMemecraft.sol";
import "forge-std/console.sol";

library BackupLogic {

    uint public constant WORLD_NUM_ELEMENTS         = 4;
    uint public constant WORLD_TREE_HEIGHT          = 3;
    uint public constant WORLD_CHARACTERS_INDEX     = 2;
    uint public constant WORLD_MONSTERS_INDEX       = 3;
    uint public constant CHARACTERS_NUM_ELEMENTS    = 128;
    uint public constant CHARACTERS_TREE_HEIGHT     = 8;
    uint public constant MONSTERS_NUM_ELEMENTS      = 128;
    uint public constant MONSTERS_TREE_HEIGHT       = 8;
    uint public constant CHARACTER_NUM_ELEMENTS     = 4;
    uint public constant CHARACTER_TREE_HEIGHT      = 3;
    uint public constant MONSTER_NUM_ELEMENTS       = 7;
    uint public constant MONSTER_TREE_HEIGHT        = 4;

    function proofCharacter(
        IWorldOfMemecraft.Character memory character,
        bytes32 backupRoot,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        return _merkleProof(
            backupRoot,
            merkleizeCharacter(character),
            WORLD_CHARACTERS_INDEX << (CHARACTERS_TREE_HEIGHT - 1) | character.id,
            proof
        );
    }

    function proofMonster(
        IWorldOfMemecraft.Monster memory monster,
        bytes32 backupRoot,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        return _merkleProof(
            backupRoot,
            merkleizeMonster(monster),
            WORLD_MONSTERS_INDEX << (MONSTERS_TREE_HEIGHT - 1) | monster.id,
            proof
        );
    }

    function merkleizeWorld(
        IWorldOfMemecraft.World storage world
    ) internal view returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](WORLD_NUM_ELEMENTS);
        hashed[0] = keccak256(abi.encode(world.servername));
        hashed[1] = keccak256(abi.encode(world.numPlayers));
        hashed[2] = merkleizeCharacters(world.characters);
        hashed[3] = merkleizeMonsters(world.monsters);
        return merkleize(hashed);
    }

    function merkleizeCharacters(
        IWorldOfMemecraft.Character[] memory characters
    ) internal pure returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](CHARACTERS_NUM_ELEMENTS);
        for (uint i; i < characters.length; i++) {
            hashed[i] = merkleizeCharacter(characters[i]);
        }
        console.log("characters");
        console.logBytes32(merkleize(hashed));
        return merkleize(hashed);
    }

    function merkleizeCharacter(
        IWorldOfMemecraft.Character memory character
    ) internal pure returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](CHARACTER_NUM_ELEMENTS);
        hashed[0] = keccak256(abi.encode(character.id));
        hashed[1] = keccak256(abi.encode(character.level));
        hashed[2] = keccak256(abi.encode(character.health));
        hashed[3] = keccak256(abi.encode(character.xp));
        console.log("character");
        console.logBytes32(merkleize(hashed));
        return merkleize(hashed);
    }

    function merkleizeMonsters(
        IWorldOfMemecraft.Monster[] memory monsters
    ) internal pure returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](MONSTERS_NUM_ELEMENTS);
        for (uint i; i < monsters.length; i++) {
            hashed[i] = merkleizeMonster(monsters[i]);
        }
        console.log("monsters");
        console.logBytes32(merkleize(hashed));
        return merkleize(hashed);
    }

    function merkleizeMonster(
        IWorldOfMemecraft.Monster memory monster
    ) internal pure returns (bytes32) {
        bytes32[] memory hashed = new bytes32[](MONSTER_NUM_ELEMENTS);
        hashed[0] = keccak256(abi.encode(monster.id));
        hashed[1] = keccak256(abi.encode(monster.name));
        hashed[2] = keccak256(abi.encode(monster.level));
        hashed[3] = keccak256(abi.encode(monster.health));
        hashed[4] = keccak256(abi.encode(monster.kills));
        hashed[5] = keccak256(abi.encode(monster.xpDrop));
        hashed[6] = keccak256(abi.encode(monster.alive));
        console.log("monster");
        console.logBytes32(merkleize(hashed));
        return merkleize(hashed);
    }

    function merkleize(bytes32[] memory input) internal pure returns (bytes32) {
        uint256 n = _upperPow2(input.length);
        bytes32[] memory cache = new bytes32[](n);
        for (uint256 i = 0; i < input.length; i++) {
            cache[i] = input[i];
        }
        n /= 2;
        while (n > 0) {
            for (uint256 i = 0; i < n; i++) {
                (bytes32 l, bytes32 r) = (cache[2 * i], cache[2 * i + 1]);
                if (r == bytes32(0))
                    if (l == bytes32(0))
                        cache[i] = bytes32(0);
                    else
                        cache[i] = keccak256(abi.encodePacked(l, l));
                else
                    cache[i] = keccak256(abi.encodePacked(l, r));
            }
            n /= 2;
        }
        return cache[0];
    }

    function _upperPow2(uint n) private pure returns (uint32 x) {
        x = 1;
        while (n > x) {
            x <<= 1;
        }
    }

    function _merkleProof(bytes32 root, bytes32 leaf, uint path, bytes32[] memory proof) private pure returns (bool) {
        bytes32 hashed = leaf;
        for (uint i; i < proof.length; i++) {
            if (path % 2 == 0) {
                hashed = keccak256(abi.encodePacked(hashed, proof[i]));
            } else {
                hashed = keccak256(abi.encodePacked(proof[i], hashed));
            }
            path >>= 1;
        }
        return root == hashed;
    }
}


