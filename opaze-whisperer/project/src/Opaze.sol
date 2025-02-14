// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC721} from "src/ERC721.sol";

contract Opaze is ERC721 {

    bool public minted;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {}

    function mintTo(address recipient) public payable returns (uint256) {
        require(!minted, "Already minted");
        minted = !minted;
        _mint(recipient, 1);
        return 1;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return "";
    }
}
