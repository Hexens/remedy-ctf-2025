// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IwstEth {
    /// @notice Gets the amount of wstEth tokens per stEth token.
    /// @return amount of wstETH for a 1 stETH
    function tokensPerStEth() external view returns (uint256);

    /// @notice Get amount of stETH for a one wstETH
    /// @return amount of stETH for 1 wstETH
    function stEthPerToken() external view returns (uint256);

    /// @notice Returns address of stEth contract.
    function stETH() external view returns (address);
}
