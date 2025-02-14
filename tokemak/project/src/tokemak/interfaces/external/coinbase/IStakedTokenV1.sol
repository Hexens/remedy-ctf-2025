// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStakedTokenV1 {
    function exchangeRate() external view returns (uint256 _exchangeRate);
}
