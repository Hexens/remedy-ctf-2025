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
import { AuraStaking } from "src/tokemak/destinations/adapters/staking/AuraAdapter.sol";
import { IConvexBooster } from "src/tokemak/interfaces/external/convex/IConvexBooster.sol";
import { AuraRewards } from "src/tokemak/destinations/adapters/rewards/AuraRewardsAdapter.sol";
import { BalancerBeethovenAdapter } from "src/tokemak/destinations/adapters/BalancerBeethovenAdapter.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { IncentiveCalculatorBase } from "src/tokemak/stats/calculators/base/IncentiveCalculatorBase.sol";

/// @title Destination Vault to proxy a Balancer Pool that goes into Aura
contract BalancerAuraDestinationVault is DestinationVault {
    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Pool and LP token this vault proxies
        address balancerPool;
        /// @notice Aura reward contract
        address auraStaking;
        /// @notice Aura Booster contract
        address auraBooster;
        /// @notice Numeric pool id used to reference Balancer pool
        uint256 auraPoolId;
    }

    string internal constant EXCHANGE_NAME = "balancer";

    /// @notice Balancer Vault
    IVault public immutable balancerVault;

    /// @notice Token minted during reward claiming. Specific to Convex-style rewards. Aura in this case.
    address public immutable defaultRewardToken;

    /// @notice Pool tokens changed – possible for Balancer pools with no liquidity
    error PoolTokensChanged(IERC20[] cachedTokens, IERC20[] actualTokens);

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    IERC20[] internal poolTokens;

    /// @notice Pool and LP token this vault proxies
    address public balancerPool;

    /// @notice Aura reward contract
    address public auraStaking;

    /// @notice Aura Booster contract
    address public auraBooster;

    /// @notice Numeric pool id used to reference balancer pool
    uint256 public auraPoolId;

    /// @notice Whether the balancePool is a ComposableStable pool. false -> MetaStable
    bool public isComposable;

    constructor(
        ISystemRegistry sysRegistry,
        address _balancerVault,
        address _defaultStakingRewardToken
    ) DestinationVault(sysRegistry) {
        Errors.verifyNotZero(_balancerVault, "_balancerVault");
        Errors.verifyNotZero(_defaultStakingRewardToken, "_defaultStakingRewardToken");

        // Both are checked above
        // slither-disable-next-line missing-zero-check
        balancerVault = IVault(_balancerVault);
        // slither-disable-next-line missing-zero-check
        defaultRewardToken = _defaultStakingRewardToken;
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
        Errors.verifyNotZero(initParams.auraStaking, "auraStaking");
        Errors.verifyNotZero(initParams.auraBooster, "auraBooster");
        Errors.verifyNotZero(initParams.auraPoolId, "auraPoolId");

        balancerPool = initParams.balancerPool;
        auraStaking = initParams.auraStaking;
        auraBooster = initParams.auraBooster;
        auraPoolId = initParams.auraPoolId;
        isComposable = BalancerUtilities.isComposablePool(initParams.balancerPool);

        // Base class has the initializer() modifier to prevent double-setup
        // If you don't call the base initialize, make sure you protect this call
        super.initialize(baseAsset_, underlyer_, rewarder_, incentiveCalculator_, additionalTrackedTokens_, params_);

        // Tokens that are used by the proxied pool cannot be removed from the vault
        // via recover(). Make sure we track those tokens here.
        // slither-disable-next-line unused-return
        (poolTokens,) = BalancerUtilities._getPoolTokens(balancerVault, balancerPool);
        if (poolTokens.length == 0) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            _addTrackedToken(address(poolTokens[i]));
        }
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault all underlyer should be staked externally, so internal debt should be 0.
    function internalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault all underlyer should be staked, and mint is 1:1, so external debt is `totalSupply()`.
    function externalDebtBalance() public view override returns (uint256) {
        return totalSupply();
    }

    /// @notice Get the balance of underlyer currently staked in Aura
    /// @return Balance of underlyer currently staked in Aura
    function externalQueriedBalance() public view override returns (uint256) {
        return IERC20(auraStaking).balanceOf(address(this));
    }

    /// @inheritdoc IDestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc IDestinationVault
    function poolType() external view virtual override returns (string memory) {
        return isComposable ? "balCompStable" : "balMetaStable";
    }

    /// @inheritdoc IDestinationVault
    /// @notice Balancer pools do not deal in ETH
    function poolDealInEth() external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IDestinationVault
    function underlyingTotalSupply() external view virtual override returns (uint256) {
        return isComposable
            ? IBalancerComposableStablePool(_underlying).getActualSupply()
            : IERC20(_underlying).totalSupply();
    }

    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view virtual override returns (address[] memory ret) {
        if (isComposable) {
            uint256 len = poolTokens.length;
            ret = new address[](len - 1);
            uint256 bptIndex = IBalancerComposableStablePool(balancerPool).getBptIndex();
            uint256 h = 0;
            for (uint256 i = 0; i < len; ++i) {
                if (i != bptIndex) {
                    ret[h] = address(poolTokens[i]);
                    h++;
                }
            }
        } else {
            ret = BalancerUtilities._convertERC20sToAddresses(poolTokens);
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
        // We should verify if pool tokens didn't change before staking to make sure we're staking for the same tokens
        // slither-disable-next-line unused-return
        (IERC20[] memory queriedPoolTokens,) = BalancerUtilities._getPoolTokens(balancerVault, balancerPool);

        uint256 nTokens = poolTokens.length;
        if (nTokens != queriedPoolTokens.length) {
            revert PoolTokensChanged(poolTokens, queriedPoolTokens);
        }

        for (uint256 i = 0; i < nTokens; ++i) {
            if (poolTokens[i] != queriedPoolTokens[i]) {
                revert PoolTokensChanged(poolTokens, queriedPoolTokens);
            }
        }

        // Stake LPs into Aura
        AuraStaking.depositAndStake(IConvexBooster(auraBooster), _underlying, auraStaking, auraPoolId, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(
        uint256 amount
    ) internal virtual override {
        AuraStaking.withdrawStake(balancerPool, auraStaking, amount);
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) = AuraRewards.claimRewards(auraStaking, defaultRewardToken, msg.sender, _trackedTokens);
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(
        uint256 underlyerAmount
    ) internal virtual override returns (address[] memory tokens, uint256[] memory amounts) {
        // Min amounts are intentionally 0. This fn is only called during a
        // user initiated withdrawal where they've accounted for slippage
        // at the router or otherwise
        uint256[] memory minAmounts = new uint256[](poolTokens.length);
        tokens = BalancerUtilities._convertERC20sToAddresses(poolTokens);
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
        address calcLp = IncentiveCalculatorBase(incentiveCalculator).lpToken();
        address calcPool = IncentiveCalculatorBase(incentiveCalculator).pool();

        if (calcLp != _underlying) {
            revert InvalidIncentiveCalculator(calcLp, _underlying, "lp");
        }
        if (calcPool != balancerPool) {
            revert InvalidIncentiveCalculator(calcPool, balancerPool, "pool");
        }
    }
}
