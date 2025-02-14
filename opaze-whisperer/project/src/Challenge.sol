// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/Opaze.sol";
import "src/OpazeWhisperer.sol";

contract Challenge {
    address public immutable PLAYER;
    Opaze public immutable OPAZE;
    OpazeWhisperer public immutable OPAZEWHISPERER;

    bool private solved;

    constructor(address player,address _opaze, address _opazeWhisperer) {
        PLAYER = player;
        
        OPAZEWHISPERER = OpazeWhisperer(_opazeWhisperer);
        OPAZE = Opaze(_opaze);
        OPAZE.mintTo(_opazeWhisperer);
    }

    function solve() external {
        require(OPAZE.ownerOf(1) == PLAYER, "You must own the Opaze");
        solved = true;
    }

    function isSolved() external view returns (bool) {
        return solved;
    }
}
