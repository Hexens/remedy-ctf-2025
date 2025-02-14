// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOEth {
    function rebasingCreditsPerToken() external view returns (uint256);
}
