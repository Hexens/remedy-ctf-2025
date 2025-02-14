// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { IPool } from "src/tokemak/interfaces/external/curve/IPool.sol";
import { DestinationVault, IDestinationVault } from "src/tokemak/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ICurveResolver } from "src/tokemak/interfaces/utils/ICurveResolver.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IConvexBooster } from "src/tokemak/interfaces/external/convex/IConvexBooster.sol";
import { ConvexStaking } from "src/tokemak/destinations/adapters/staking/ConvexAdapter.sol";
import { IBaseRewardPool } from "src/tokemak/interfaces/external/convex/IBaseRewardPool.sol";
import { ConvexRewards } from "src/tokemak/destinations/adapters/rewards/ConvexRewardsAdapter.sol";
import { CurveV2FactoryCryptoAdapter } from "src/tokemak/destinations/adapters/CurveV2FactoryCryptoAdapter.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IncentiveCalculatorBase } from "src/tokemak/stats/calculators/base/IncentiveCalculatorBase.sol";

/// @notice Destination Vault to proxy a Curve Pool that goes into Convex
/// @dev Supports Curve V1 StableSwap, Curve V2 CryptoSwap, and Curve stETH/ETH-ng Pool
contract CurveConvexDestinationVault is DestinationVault {
    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Pool this vault proxies
        address curvePool;
        /// @notice Convex reward contract
        address convexStaking;
        /// @notice Numeric pool id used to reference Curve pool
        uint256 convexPoolId;
    }

    string private constant EXCHANGE_NAME = "curve";

    /// @notice Coin index of token we'll perform withdrawals to
    address public immutable defaultStakingRewardToken;

    /// @notice Invalid coin index was provided for withdrawal
    error InvalidBaseTokenBurnIndex(uint256 provided, uint256 numTokens);

    /// @notice Pool is shutdown
    error PoolShutdown();

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    /// @notice Pool this vault proxies
    address public curvePool;

    /// @notice LP token this vault proxies
    /// @dev May be same as curvePool, depends on the pool type
    address public curveLpToken;

    /// @notice Convex reward contract
    address public convexStaking;

    /// @notice Convex Booster contract
    address public immutable convexBooster;

    /// @notice Numeric pool id used to reference Curve pool
    uint256 public convexPoolId;

    /// @notice True for Curve V1 (StableSwap), false for V2 (CryptoSwap).
    bool public isStableSwap;

    /// @notice Whether the pool deals in ETH
    /// @dev false by default
    /// @dev Exposed via `poolDealInEth()`
    /// @dev Set in `initialize()`
    bool private _poolDealInEth;

    /// @dev Tokens that make up the LP token. Meta tokens not broken up
    address[] private constituentTokens;

    /// @dev Always 0, used as min amounts during withdrawals
    uint256[] internal minAmounts;

    constructor(
        ISystemRegistry sysRegistry,
        address _defaultStakingRewardToken,
        address _convexBooster
    ) DestinationVault(sysRegistry) {
        // Zero is valid here if no default token is minted by the reward system
        // slither-disable-next-line missing-zero-check
        defaultStakingRewardToken = _defaultStakingRewardToken;

        Errors.verifyNotZero(_convexBooster, "_convexBooster");
        // slither-disable-next-line missing-zero-check
        convexBooster = _convexBooster;
    }

    ///@notice Support ETH operations
    receive() external payable { }

    /// @inheritdoc DestinationVault
    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) public virtual override {
        // Decode the init params, validate, and save off
        // Run before the base initialize as _validateCalculator() relies on them being set
        InitParams memory initParams = abi.decode(params_, (InitParams));
        Errors.verifyNotZero(initParams.curvePool, "curvePool");
        Errors.verifyNotZero(initParams.convexStaking, "convexStaking");

        curvePool = initParams.curvePool;
        convexStaking = initParams.convexStaking;
        convexPoolId = initParams.convexPoolId;

        // Base class has the initializer() modifier to prevent double-setup
        // If you don't call the base initialize, make sure you protect this call
        super.initialize(baseAsset_, underlyer_, rewarder_, incentiveCalculator_, additionalTrackedTokens_, params_);

        // We must configure a the curve resolver to setup the vault
        ICurveResolver curveResolver = systemRegistry.curveResolver();
        Errors.verifyNotZero(address(curveResolver), "curveResolver");

        // Setup pool tokens as tracked. If we want to handle meta pools and their tokens
        // we will pass them in as additional, not currently a use case
        // slither-disable-next-line unused-return
        (address[8] memory tokens, uint256 numTokens, address curveQueriedLpToken, bool queriedIsStableSwap) =
            curveResolver.resolveWithLpToken(initParams.curvePool);

        Errors.verifyNotZero(numTokens, "numTokens");

        // slither-disable-next-line unused-return
        (address lpToken,,, address crvRewards,, bool _isShutdown) =
            IConvexBooster(convexBooster).poolInfo(initParams.convexPoolId);

        if (_isShutdown) {
            revert PoolShutdown();
        }

        Errors.verifyNotZero(lpToken, "lpToken");

        if (curveQueriedLpToken != lpToken) {
            revert Errors.InvalidParam("lpToken");
        }

        if (crvRewards != initParams.convexStaking) {
            revert Errors.InvalidParam("crvRewards");
        }

        bool memoryPoolDealInEth = false;
        for (uint256 i = 0; i < numTokens; ++i) {
            address weth = address(systemRegistry.weth());
            address token = tokens[i];
            if (!memoryPoolDealInEth && tokens[i] == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
                token = weth;
                memoryPoolDealInEth = true;
            }

            _addTrackedToken(token);
            constituentTokens.push(token);
        }
        _poolDealInEth = memoryPoolDealInEth;

        // Initialize our min amounts for withdrawals to 0 for all tokens
        minAmounts = new uint256[](numTokens);

        // Checked above
        // slither-disable-next-line missing-zero-check
        curveLpToken = lpToken;

        isStableSwap = queriedIsStableSwap;
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

    /// @notice Get the balance of underlyer currently staked in Convex
    /// @return Balance of underlyer currently staked in Convex
    function externalQueriedBalance() public view override returns (uint256) {
        return IBaseRewardPool(convexStaking).balanceOf(address(this));
    }

    /// @inheritdoc IDestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc IDestinationVault
    function poolType() external view virtual override returns (string memory) {
        return isStableSwap ? "curveV1" : "curveV2";
    }

    /// @inheritdoc IDestinationVault
    function poolDealInEth() external view virtual override returns (bool) {
        return _poolDealInEth;
    }

    /// @inheritdoc IDestinationVault
    function underlyingTotalSupply() external view virtual override returns (uint256) {
        return IERC20(_underlying).totalSupply();
    }

    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view override returns (address[] memory result) {
        uint256 len = constituentTokens.length;
        result = new address[](len);
        for (uint256 i = 0; i < len; ++i) {
            result[i] = constituentTokens[i];
        }
    }

    /// @inheritdoc IDestinationVault
    function underlyingReserves() external view override returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 len = constituentTokens.length;
        tokens = new address[](len);
        amounts = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            tokens[i] = constituentTokens[i];
            amounts[i] = IPool(curvePool).balances(i);
        }
    }

    /// @notice Callback during a deposit after the sender has been minted shares (if applicable)
    /// @dev Should be used for staking tokens into protocols, etc
    /// @param amount underlying tokens received
    function _onDeposit(
        uint256 amount
    ) internal virtual override {
        ConvexStaking.depositAndStake(IConvexBooster(convexBooster), _underlying, convexStaking, convexPoolId, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(
        uint256 amount
    ) internal virtual override {
        ConvexStaking.withdrawStake(_underlying, convexStaking, amount);
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) =
            ConvexRewards.claimRewards(convexStaking, defaultStakingRewardToken, msg.sender, _trackedTokens);
    }

    // slither-disable-start dead-code
    /// @inheritdoc DestinationVault
    function _burnUnderlyer(
        uint256 underlyerAmount
    ) internal virtual override returns (address[] memory tokens, uint256[] memory amounts) {
        // We withdraw everything in one coin to ease swapping
        // re: minAmount == 0, this call is only made during a user initiated withdraw where slippage is
        // controlled for at the router

        // We always want our tokens back in WETH so useEth false
        (tokens, amounts) = CurveV2FactoryCryptoAdapter.removeLiquidity(
            minAmounts, underlyerAmount, curvePool, curveLpToken, IWETH9(systemRegistry.weth())
        );
    }
    // slither-disable-end dead-code

    /// @inheritdoc DestinationVault
    function getPool() public view override returns (address) {
        return curvePool;
    }

    function _validateCalculator(
        address incentiveCalculator
    ) internal view override {
        address calcLp = IncentiveCalculatorBase(incentiveCalculator).lpToken();
        address calcPool = IncentiveCalculatorBase(incentiveCalculator).pool();

        if (calcLp != _underlying) {
            revert InvalidIncentiveCalculator(calcLp, _underlying, "lp");
        }
        if (calcPool != curvePool) {
            revert InvalidIncentiveCalculator(calcPool, curvePool, "pool");
        }
    }
}
