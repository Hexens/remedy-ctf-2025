// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Gets price of rEth from L1 Ethereum
interface IRocketOvmPriceOracle {
    /**
     * @notice Returns rate of rEth to Eth
     * @dev Always returns price with Eth denomination, 18 decimals of precision
     */
    function rate() external view returns (uint256);
}
