// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IBalancerPool is IERC20Metadata {
    /// @notice returns total supply of Balancer pool
    function totalSupply() external view returns (uint256);

    /**
     * @notice gets Balancer poolId
     * @return bytes32 poolId
     */
    function getPoolId() external view returns (bytes32);
}
