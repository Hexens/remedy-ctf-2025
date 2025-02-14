// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWstEth {
    /**
     * @notice Gets the amount of wstEth tokens per stEth token.
     * @dev returns answer in 18 decimals of precision.
     */
    function tokensPerStEth() external view returns (uint256);

    /// @notice Returns address of stEth contract.
    function stETH() external view returns (address);
}
