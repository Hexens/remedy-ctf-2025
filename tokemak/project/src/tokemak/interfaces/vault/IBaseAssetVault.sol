// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IBaseAssetVault {
    /// @notice Asset that this Vault primarily manages
    /// @dev Vault decimals should be the same as the baseAsset
    function baseAsset() external view returns (address);
}
