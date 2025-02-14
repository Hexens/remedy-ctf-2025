// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IRateProvider } from "src/tokemak/interfaces/external/balancer/IRateProvider.sol";

interface IBalancerMetaStablePool {
    function getPoolId() external view returns (bytes32);

    function getRate() external view returns (uint256);

    function getLastInvariant() external view returns (uint256);

    function getLatest(
        uint8 x
    ) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getSwapFeePercentage() external view returns (uint256);

    function getRateProviders() external view returns (IRateProvider[] memory);
}
