// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface ILRTOracle {
    /// @notice Returns RsEth price.
    function rsETHPrice() external view returns (uint256);
}
