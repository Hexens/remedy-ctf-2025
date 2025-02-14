// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "src/openzeppelin-contracts/token/ERC20/ERC20.sol";

contract PoolToken is ERC20 {

    address public immutable OWNER;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        OWNER = msg.sender;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == OWNER);
        _mint(to, amount);
    }
}