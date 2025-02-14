// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IBalancerComposableStablePool {
    function getActualSupply() external view returns (uint256);

    function getBptIndex() external view returns (uint256);

    function getPoolId() external view returns (bytes32);

    function getRate() external view returns (uint256);

    function getTokenRate(
        IERC20 token
    ) external view returns (uint256);

    function isTokenExemptFromYieldProtocolFee(
        address token
    ) external view returns (bool);
}
