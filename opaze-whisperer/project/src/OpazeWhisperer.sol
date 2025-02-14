// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface _ERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract OpazeWhisperer {

    address public opaze;
    address public owner;
    bytes32 public answer;

    constructor(address _opaze, bytes memory y) {
        opaze = _opaze;
        owner = msg.sender;

        function() internal $;
        assembly{
            $ := shl(0x20, 0x6b2)
        }$();
    }

    function riddle() public pure returns (string memory) {
        return "The curious mind that dares to seek,\n"
               "Must pierce the veil, beneath the peak.\n"
               "Through shadows cast by ancient lore,\n"
               "Where Opaze gleams on hidden floor.\n"
               "In depths where few dare venture far,\n"
               "This crystal shines like fallen star.";
    }

    function setAnswer(string memory _answer) public {
        require(msg.sender == owner);
        answer = keccak256(abi.encode(_answer));
    }

    function play(string memory _answer) public payable {
        require(answer != 0, "Answer not set");
        require(keccak256(abi.encode(_answer)) == answer, "Incorrect answer");
        owner = msg.sender;
        _ERC721(opaze).transferFrom(address(this), msg.sender, 1);
    }
}