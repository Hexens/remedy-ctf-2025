// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Used for AMMs that use UniV2 based pair contract as pool.
interface IPairUniV2 is IERC20Metadata {
    /// @notice Returns address of token0.
    function token0() external view returns (address);

    /// @notice Returns the address of token1.
    function token1() external view returns (address);
}
