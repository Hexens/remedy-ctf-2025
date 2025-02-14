// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

contract Burner {
    constructor() {
        
    }

    function destruct() external {
        selfdestruct(payable(address(this)));
    }
}