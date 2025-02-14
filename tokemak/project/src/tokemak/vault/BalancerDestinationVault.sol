// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { DestinationVault, IDestinationVault } from "src/tokemak/vault/DestinationVault.sol";
import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";
import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { BalancerBeethovenAdapter } from "src/tokemak/destinations/adapters/BalancerBeethovenAdapter.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { BalancerStablePoolCalculatorBase } from "src/tokemak/stats/calculators/base/BalancerStablePoolCalculatorBase.sol";

/// @title Destination Vault to proxy a Balancer Pool that holds the LP asset
contract BalancerDestinationVault is DestinationVault {
    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Pool and LP token this vault proxies
        address balancerPool;
    }

    string internal constant EXCHANGE_NAME = "balancer";

    /// @notice Balancer Vault
    IVault public immutable balancerVault;

    /// @notice Pool tokens changed – possible for Balancer pools with no liquidity
    error PoolTokensChanged(IERC20[] cachedTokens, IERC20[] actualTokens);

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    address[] internal poolTokens;

    /// @notice Pool and LP token this vault proxies
    address public balancerPool;

    /// @notice Whether the balancePool is a ComposableStable pool. false -> MetaStable
    bool public isComposable;

    constructor(ISystemRegistry sysRegistry, address _balancerVault) DestinationVault(sysRegistry) {
        Errors.verifyNotZero(_balancerVault, "_balancerVault");

        // Checked above
        // slither-disable-next-line missing-zero-check
        balancerVault = IVault(_balancerVault);
    }

    /// @inheritdoc DestinationVault
    function initialize(
        IERC20Metadata baseAsset_,
        IERC20Metadata underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) public virtual override {
        // Decode the init params, validate, and save off
        // Run before the base initialize as _validateCalculator() relies on them being set
        InitParams memory initParams = abi.decode(params_, (InitParams));
        Errors.verifyNotZero(initParams.balancerPool, "balancerPool");

        balancerPool = initParams.balancerPool;
        isComposable = BalancerUtilities.isComposablePool(initParams.balancerPool);

        // Base class has the initializer() modifier to prevent double-setup
        // If you don't call the base initialize, make sure you protect this call
        super.initialize(baseAsset_, underlyer_, rewarder_, incentiveCalculator_, additionalTrackedTokens_, params_);

        // Tokens that are used by the proxied pool cannot be removed from the vault
        // via recover(). Make sure we track those tokens here.
        // slither-disable-next-line unused-return
        (IERC20[] memory _poolTokens,) = BalancerUtilities._getPoolTokens(balancerVault, balancerPool);
        if (_poolTokens.length == 0) revert ArrayLengthMismatch();

        poolTokens = BalancerUtilities._convertERC20sToAddresses(_poolTokens);
        for (uint256 i = 0; i < poolTokens.length; ++i) {
            _addTrackedToken(poolTokens[i]);
        }
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault no underlyer should be staked externally, so external debt should be 0.
    function internalDebtBalance() public view override returns (uint256) {
        return totalSupply();
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault no underlyer should be staked.
    function externalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    /// @notice Get the balance of underlyer currently staked outside the Vault
    /// @return Return 0 as no LP token is deployed outsie of vault
    function externalQueriedBalance() public pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IDestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc IDestinationVault
    function poolType() external view override returns (string memory) {
        return isComposable ? "balCompStable" : "balMetaStable";
    }

    /// @inheritdoc IDestinationVault
    /// @notice Balancer pools do not deal in ETH
    function poolDealInEth() external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IDestinationVault
    function underlyingTotalSupply() external view override returns (uint256) {
        return isComposable
            ? IBalancerComposableStablePool(_underlying).getActualSupply()
            : IERC20(_underlying).totalSupply();
    }

    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view override returns (address[] memory ret) {
        if (isComposable) {
            // slither-disable-next-line unused-return
            (IERC20[] memory tokens,) = BalancerUtilities._getComposablePoolTokensSkipBpt(balancerVault, balancerPool);
            ret = BalancerUtilities._convertERC20sToAddresses(tokens);
        } else {
            ret = poolTokens;
        }
    }

    /// @inheritdoc IDestinationVault
    function underlyingReserves() external view override returns (address[] memory tokens, uint256[] memory amounts) {
        (IERC20[] memory queriedPoolTokens, uint256[] memory queriedBalances) =
            BalancerUtilities._getPoolTokens(balancerVault, balancerPool);

        tokens = BalancerUtilities._convertERC20sToAddresses(queriedPoolTokens);
        amounts = queriedBalances;
    }

    /// @inheritdoc DestinationVault
    function _onDeposit(
        uint256 amount
    ) internal virtual override {
        // Accept LP tokens and do nothing
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(
        uint256 amount
    ) internal virtual override {
        // Do nothing, LP balance exists
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        // Do nothing and return empty amounts and tokens
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(
        uint256 underlyerAmount
    ) internal virtual override returns (address[] memory tokens, uint256[] memory amounts) {
        // Min amounts are intentionally 0. This fn is only called during a
        // user initiated withdrawal where they've accounted for slippage
        // at the router or otherwise
        uint256[] memory minAmounts = new uint256[](poolTokens.length);
        tokens = poolTokens;
        amounts =
            BalancerBeethovenAdapter.removeLiquidity(balancerVault, balancerPool, tokens, minAmounts, underlyerAmount);
    }

    /// @inheritdoc DestinationVault
    function getPool() public view override returns (address) {
        return balancerPool;
    }

    function _validateCalculator(
        address incentiveCalculator
    ) internal view override {
        address calcPool = BalancerStablePoolCalculatorBase(incentiveCalculator).poolAddress();
        // Should be the same because its Balancer, but checking anyways
        if (calcPool != _underlying) {
            revert InvalidIncentiveCalculator(calcPool, _underlying, "lp");
        }
        if (calcPool != balancerPool) {
            revert InvalidIncentiveCalculator(calcPool, balancerPool, "pool");
        }
    }
}
