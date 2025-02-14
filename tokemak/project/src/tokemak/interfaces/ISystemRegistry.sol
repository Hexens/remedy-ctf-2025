// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { IAccToke } from "src/tokemak/interfaces/staking/IAccToke.sol";
import { IAutopoolRegistry } from "src/tokemak/interfaces/vault/IAutopoolRegistry.sol";
import { IAccessController } from "src/tokemak/interfaces/security/IAccessController.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";
import { ICurveResolver } from "src/tokemak/interfaces/utils/ICurveResolver.sol";
import { IAutopilotRouter } from "src/tokemak/interfaces/vault/IAutopilotRouter.sol";
import { IAutopoolFactory } from "src/tokemak/interfaces/vault/IAutopoolFactory.sol";
import { ISystemSecurity } from "src/tokemak/interfaces/security/ISystemSecurity.sol";
import { IDestinationRegistry } from "src/tokemak/interfaces/destinations/IDestinationRegistry.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { IDestinationVaultRegistry } from "src/tokemak/interfaces/vault/IDestinationVaultRegistry.sol";
import { IAccessController } from "src/tokemak/interfaces/security/IAccessController.sol";
import { IStatsCalculatorRegistry } from "src/tokemak/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IAsyncSwapperRegistry } from "src/tokemak/interfaces/liquidation/IAsyncSwapperRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IIncentivesPricingStats } from "src/tokemak/interfaces/stats/IIncentivesPricingStats.sol";
import { IMessageProxy } from "src/tokemak/interfaces/messageProxy/IMessageProxy.sol";

/// @notice Root most registry contract for the system
interface ISystemRegistry {
    /// @notice Get the TOKE contract for the system
    /// @return toke instance of TOKE used in the system
    function toke() external view returns (IERC20Metadata);

    /// @notice Get the referenced WETH contract for the system
    /// @return weth contract pointer
    function weth() external view returns (IWETH9);

    /// @notice Get the AccToke staking contract
    /// @return accToke instance of the accToke contract for the system
    function accToke() external view returns (IAccToke);

    /// @notice Get the AutopoolRegistry for this system
    /// @return registry instance of the registry for this system
    function autoPoolRegistry() external view returns (IAutopoolRegistry registry);

    /// @notice Get the destination Vault registry for this system
    /// @return registry instance of the registry for this system
    function destinationVaultRegistry() external view returns (IDestinationVaultRegistry registry);

    /// @notice Get the access Controller for this system
    /// @return controller instance of the access controller for this system
    function accessController() external view returns (IAccessController controller);

    /// @notice Get the destination template registry for this system
    /// @return registry instance of the registry for this system
    function destinationTemplateRegistry() external view returns (IDestinationRegistry registry);

    /// @notice Auto Pilot Router
    /// @return router instance of the system
    function autoPoolRouter() external view returns (IAutopilotRouter router);

    /// @notice Vault factory lookup by type
    /// @return vaultFactory instance of the vault factory for this vault type
    function getAutopoolFactoryByType(
        bytes32 vaultType
    ) external view returns (IAutopoolFactory vaultFactory);

    /// @notice Get the stats calculator registry for this system
    /// @return registry instance of the registry for this system
    function statsCalculatorRegistry() external view returns (IStatsCalculatorRegistry registry);

    /// @notice Get the root price oracle for this system
    /// @return oracle instance of the root price oracle for this system
    function rootPriceOracle() external view returns (IRootPriceOracle oracle);

    /// @notice Get the async swapper registry for this system
    /// @return registry instance of the registry for this system
    function asyncSwapperRegistry() external view returns (IAsyncSwapperRegistry registry);

    /// @notice Get the swap router for this system
    /// @return router instance of the swap router for this system
    function swapRouter() external view returns (ISwapRouter router);

    /// @notice Get the curve resolver for this system
    /// @return resolver instance of the curve resolver for this system
    function curveResolver() external view returns (ICurveResolver resolver);

    /// @notice Verify if given address is registered as Reward Token
    /// @param rewardToken token address to verify
    /// @return bool that indicates true if token is registered and false if not
    function isRewardToken(
        address rewardToken
    ) external view returns (bool);

    /// @notice Get the system security instance for this system
    /// @return security instance of system security for this system
    function systemSecurity() external view returns (ISystemSecurity security);

    /// @notice Get the Incentive Pricing Stats
    /// @return incentivePricing the incentive pricing contract
    function incentivePricing() external view returns (IIncentivesPricingStats);

    /// @notice Get the Message Proxy
    /// @return Message proxy contract
    function messageProxy() external view returns (IMessageProxy);

    /// @notice Get the receiving router contract.
    /// @return Receiving router contract
    function receivingRouter() external view returns (address);

    /// @notice Check if an additional contract of type is valid in the system
    /// @return True if the contract is a valid for the given type
    function isValidContract(bytes32 contractType, address contractAddress) external view returns (bool);

    /// @notice Returns the additional contract of the given type
    /// @dev Revert if not set
    function getUniqueContract(
        bytes32 contractType
    ) external view returns (address);

    /// @notice Returns all unique contracts configured
    function listUniqueContracts() external view returns (bytes32[] memory contractTypes, address[] memory addresses);

    /// @notice Returns all additional contract types configured
    function listAdditionalContractTypes() external view returns (bytes32[] memory);

    /// @notice Returns configured additional contracts by type
    /// @param contractType Type of contract to list
    function listAdditionalContracts(
        bytes32 contractType
    ) external view returns (address[] memory);
}
