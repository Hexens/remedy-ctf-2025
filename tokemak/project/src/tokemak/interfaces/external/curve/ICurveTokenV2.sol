// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase, var-name-mixedcase
/// @notice Works with Curve lp tokens version 2 and above, v1 does not expose a public `minter()` method.
interface ICurveTokenV2 {
    /// @notice Returns address of minter, which is the pool
    function minter() external view returns (address);
}
