// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

interface IAutopoolFactory {
    ///////////////////////////////////////////////////////////////////
    //                        Vault Creation
    ///////////////////////////////////////////////////////////////////

    /**
     * @notice Spin up a new AutopoolETH
     * @param strategy Strategy template address
     * @param symbolSuffix Symbol suffix of the new token
     * @param descPrefix Description prefix of the new token
     * @param salt Vault creation salt
     * @param extraParams Any extra data needed for the vault
     */
    function createVault(
        address strategy,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes32 salt,
        bytes calldata extraParams
    ) external payable returns (address newVaultAddress);

    function addStrategyTemplate(
        address strategyTemplate
    ) external;

    function removeStrategyTemplate(
        address strategyTemplate
    ) external;

    /// @notice Returns the template used to create Autopools
    function template() external returns (address);
}
