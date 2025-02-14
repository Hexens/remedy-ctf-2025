// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20, ERC20} from "src/openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "src/openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract WrappedToken is ERC20 {

    address public immutable owner;
    IERC20 public immutable underlying;
    uint256 public underlyingBalance;

    constructor(address underlying_) ERC20(
        string(abi.encodePacked("w", IERC20Metadata(underlying_).name())),
        string(abi.encodePacked("W", IERC20Metadata(underlying_).symbol()))
    ) {
        underlying = IERC20(underlying_);
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == owner);
        underlyingBalance += amount;
        _mint(to, amount);
        // underlying reverts on fail
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function addRewards(uint256 amount) public {
        require(msg.sender == owner);
        underlyingBalance += amount;
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function getRate() external view returns (uint256) {
        return underlyingBalance * 1e18 / totalSupply();
    }
}