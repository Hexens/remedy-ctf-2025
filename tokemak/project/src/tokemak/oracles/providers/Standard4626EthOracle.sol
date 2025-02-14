// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IERC4626 } from "src/tokemak/interfaces/vault/IERC4626.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IPriceOracle } from "src/tokemak/interfaces/oracles/IPriceOracle.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Price oracle for a 4626 Vault base asset priced through its conversion rate
/// @dev getPriceEth is not a view fn to support reentrancy checks. Dont actually change state.
contract Standard4626EthOracle is SystemComponent, IPriceOracle {
    IERC4626 public immutable vault;
    address public immutable underlyingAsset;
    uint256 public immutable vaultTokenOne;
    uint256 public immutable underlyingAssetOne;

    constructor(ISystemRegistry _systemRegistry, address _vault4626) SystemComponent(_systemRegistry) {
        // System registry must be properly initialized first
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "rootPriceOracle");

        Errors.verifyNotZero(_vault4626, "_vault4626");

        vault = IERC4626(_vault4626);

        vaultTokenOne = 10 ** vault.decimals();
        underlyingAsset = vault.asset();
        underlyingAssetOne = 10 ** IERC20Metadata(underlyingAsset).decimals();

        Errors.verifyNotZero(underlyingAsset, "underlyingAsset");
    }

    /// @inheritdoc IPriceOracle
    function getDescription() external view override returns (string memory) {
        return IERC20Metadata(underlyingAsset).symbol();
    }

    /// @inheritdoc IPriceOracle
    function getPriceInEth(
        address token
    ) external returns (uint256 price) {
        // This oracle is only setup to handle a single token but could possibly be
        // configured incorrectly at the root level and receive others to price.

        if (token != underlyingAsset) {
            revert Errors.InvalidToken(token);
        }

        uint256 vaultTokenPrice = systemRegistry.rootPriceOracle().getPriceInEth(address(vault));

        price = vaultTokenPrice * underlyingAssetOne / vault.convertToAssets(vaultTokenOne);
    }
}
