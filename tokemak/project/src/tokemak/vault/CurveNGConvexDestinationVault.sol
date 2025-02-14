// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { DestinationVault, IDestinationVault } from "src/tokemak/vault/DestinationVault.sol";
import { CurveConvexDestinationVault } from "src/tokemak/vault/CurveConvexDestinationVault.sol";
import { CurveV2FactoryCryptoAdapter } from "src/tokemak/destinations/adapters/CurveV2FactoryCryptoAdapter.sol";

/// @notice Destination Vault to proxy a Curve Pool that goes into Convex
/// @dev Supports newer Curve ng pools
contract CurveNGConvexDestinationVault is CurveConvexDestinationVault {
    constructor(
        ISystemRegistry sysRegistry,
        address _defaultStakingRewardToken,
        address _convexBooster
    ) CurveConvexDestinationVault(sysRegistry, _defaultStakingRewardToken, _convexBooster) { }

    /// @inheritdoc IDestinationVault
    function poolType() external view virtual override returns (string memory) {
        return "curveNG";
    }

    /// @inheritdoc IDestinationVault
    function poolDealInEth() external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(
        uint256 underlyerAmount
    ) internal virtual override returns (address[] memory tokens, uint256[] memory amounts) {
        // re: minAmount == 0, this call is only made during a user initiated withdraw where slippage is
        // controlled for at the router

        // We always want our tokens back in WETH so useEth false
        (tokens, amounts) = CurveV2FactoryCryptoAdapter.removeLiquidity(
            minAmounts, underlyerAmount, curvePool, curveLpToken, IWETH9(systemRegistry.weth()), true
        );
    }
}
