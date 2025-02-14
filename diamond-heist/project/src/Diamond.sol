// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./openzeppelin-contracts/token/ERC20/ERC20.sol";

contract Diamond is ERC20 {
    constructor(uint totalSupply_) ERC20("Diamond", "DIAMOND") {
        _mint(msg.sender, totalSupply_);
    }
}
