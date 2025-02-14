// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { DestinationVault, IDestinationVault } from "src/tokemak/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { IAerodromeGauge } from "src/tokemak/interfaces/external/aerodrome/IAerodromeGauge.sol";
import { IPool } from "src/tokemak/interfaces/external/aerodrome/IPool.sol";
import { IncentiveCalculatorBase } from "src/tokemak/stats/calculators/base/IncentiveCalculatorBase.sol";
import { AerodromeRewardsAdapter } from "src/tokemak/destinations/adapters/rewards/AerodromeRewardsAdapter.sol";
import { AerodromeStakingAdapter } from "src/tokemak/destinations/adapters/staking/AerodromeStakingAdapter.sol";
import { AerodromeAdapter } from "src/tokemak/destinations/adapters/AerodromeAdapter.sol";
import { IVoter } from "src/tokemak/interfaces/external/velodrome/IVoter.sol";

/// @title Used to interact with Aerodrome pools and exchanges
contract AerodromeDestinationVault is DestinationVault {
    /// @notice Address of the aerodrome router
    address public immutable aerodromeRouter;

    /// @notice Address of the aerodrome voter contract
    IVoter public immutable aerodromeVoter;

    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Gauge that this vault interacts with
        address aerodromeGauge;
    }

    /// @notice Name of exchange vault interacts with
    string private constant EXCHANGE_NAME = "aerodrome";

    /// @notice Address of the gauge that this contract interacts with
    address public aerodromeGauge;

    /// @notice Tokens of the pool
    address[] private constituentTokens;

    /// @notice If pool being proxied is stable or not.
    bool public isStable;

    constructor(
        ISystemRegistry _systemRegistry,
        address _aerodromeRouter,
        address _aerodromeVoter
    ) DestinationVault(_systemRegistry) {
        Errors.verifyNotZero(_aerodromeRouter, "_aerodromeRouter");
        Errors.verifyNotZero(_aerodromeVoter, "_aerodromeVoter");

        // slither-disable-next-line missing-zero-check
        aerodromeRouter = _aerodromeRouter;
        aerodromeVoter = IVoter(_aerodromeVoter);
    }

    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) public virtual override {
        InitParams memory initParams = abi.decode(params_, (InitParams));

        address localGauge = initParams.aerodromeGauge;
        Errors.verifyNotZero(localGauge, "localGauge");

        super.initialize(baseAsset_, underlyer_, rewarder_, incentiveCalculator_, additionalTrackedTokens_, params_);

        // Gauge, pool checks
        if (aerodromeVoter.gauges(address(underlyer_)) != localGauge) revert Errors.InvalidParam("localGauge");
        if (!aerodromeVoter.isAlive(localGauge)) revert IVoter.GaugeNotAlive(localGauge);
        if (address(underlyer_) != IAerodromeGauge(localGauge).stakingToken()) {
            revert Errors.InvalidConfiguration();
        }

        aerodromeGauge = localGauge;

        IPool localPool = IPool(address(underlyer_));
        isStable = localPool.stable();
        address token0 = localPool.token0();
        address token1 = localPool.token1();
        _addTrackedToken(token0);
        _addTrackedToken(token1);

        constituentTokens.push(token0);
        constituentTokens.push(token1);
    }

    /// @inheritdoc DestinationVault
    /// @notice In this contract all underlyer should be staked, so internal will be zero.
    function internalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault all underlyer should be staked, and mint is 1:1, so external debt is `totalSupply()`.
    function externalDebtBalance() public view override returns (uint256) {
        return totalSupply();
    }

    /// @inheritdoc DestinationVault
    /// @notice Get the balance of underlyer currently staked in Aerodrome gauge
    /// @return Balance of underlyer currently staked in Aerodrome Gauge
    function externalQueriedBalance() public view override returns (uint256) {
        return IAerodromeGauge(aerodromeGauge).balanceOf(address(this));
    }

    /// @inheritdoc IDestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc IDestinationVault
    function poolType() external view override returns (string memory) {
        return isStable ? "sAMM" : "vAMM";
    }

    /// @inheritdoc IDestinationVault
    function poolDealInEth() public pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IDestinationVault
    function underlyingTotalSupply() external view virtual override returns (uint256) {
        return IERC20(_underlying).totalSupply();
    }

    /// @notice Returns two tokens in Aerodrome Pool. Tokens returns in order lower address value -> higher
    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view override returns (address[] memory _underlyingTokens) {
        _underlyingTokens = new address[](2);

        _underlyingTokens[0] = constituentTokens[0];
        _underlyingTokens[1] = constituentTokens[1];
    }

    /// @inheritdoc IDestinationVault
    function underlyingReserves() external view override returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        tokens[0] = constituentTokens[0];
        tokens[1] = constituentTokens[1];

        amounts = new uint256[](2);
        amounts[0] = IPool(_underlying).reserve0();
        amounts[1] = IPool(_underlying).reserve1();
    }

    /// @inheritdoc DestinationVault
    function _onDeposit(
        uint256 amount
    ) internal virtual override {
        AerodromeStakingAdapter.stakeLPs(aerodromeGauge, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(
        uint256 amount
    ) internal virtual override {
        AerodromeStakingAdapter.unstakeLPs(aerodromeGauge, amount);
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) = AerodromeRewardsAdapter.claimRewards(aerodromeGauge, msg.sender);
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(
        uint256 underlyerAmount
    ) internal virtual override returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        tokens[0] = constituentTokens[0];
        tokens[1] = constituentTokens[1];

        // Amounts zero on purpose
        amounts = new uint256[](2);

        // solhint-disable-next-line max-line-length
        AerodromeAdapter.AerodromeRemoveLiquidityParams memory params = AerodromeAdapter.AerodromeRemoveLiquidityParams({
            router: aerodromeRouter,
            tokens: tokens,
            amounts: amounts,
            pool: _underlying,
            stable: isStable,
            maxLpBurnAmount: underlyerAmount
        });
        amounts = AerodromeAdapter.removeLiquidity(params);
    }

    /// @inheritdoc DestinationVault
    function getPool() public view override returns (address) {
        return _underlying;
    }

    function _validateCalculator(
        address incentiveCalculator
    ) internal view override {
        address calcLp = IncentiveCalculatorBase(incentiveCalculator).lpToken();
        address calcPool = IncentiveCalculatorBase(incentiveCalculator).pool();
        address poolAndLp = _underlying;

        if (calcLp != poolAndLp) {
            revert InvalidIncentiveCalculator(calcLp, poolAndLp, "lp");
        }
        if (calcPool != poolAndLp) {
            revert InvalidIncentiveCalculator(calcPool, poolAndLp, "pool");
        }
    }
}
