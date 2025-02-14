// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILiquidityPool {
    function amountForShare(
        uint256 _share
    ) external view returns (uint256);
}
