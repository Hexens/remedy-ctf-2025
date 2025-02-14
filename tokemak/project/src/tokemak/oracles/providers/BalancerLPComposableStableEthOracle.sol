// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerBaseOracle, ISpotPriceOracle } from "src/tokemak/oracles/providers/base/BalancerBaseOracle.sol";

/// @dev This version of Bal oracles are DEPRECATED.  See BalancerV2ComposableStableMathOracle.sol for new version

/// @title Price oracle for Balancer Composable Stable pools
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract BalancerLPComposableStableEthOracle is BalancerBaseOracle {
    constructor(
        ISystemRegistry _systemRegistry,
        IVault _balancerVault
    ) BalancerBaseOracle(_systemRegistry, _balancerVault) { }

    /// @inheritdoc ISpotPriceOracle
    function getDescription() external pure override returns (string memory) {
        return "balCompStable";
    }

    function getTotalSupply_(
        address lpToken
    ) internal virtual override returns (uint256 totalSupply) {
        totalSupply = IBalancerComposableStablePool(lpToken).getActualSupply();
    }

    function getPoolTokens_(
        address pool
    ) internal virtual override returns (IERC20[] memory tokens, uint256[] memory balances) {
        (tokens, balances) = BalancerUtilities._getComposablePoolTokensSkipBpt(balancerVault, pool);
    }
}
