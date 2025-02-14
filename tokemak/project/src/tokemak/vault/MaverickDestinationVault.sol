// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { DestinationVault, IDestinationVault } from "src/tokemak/vault/DestinationVault.sol";
import { IPool } from "src/tokemak/interfaces/external/maverick/IPool.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IRouter } from "src/tokemak/interfaces/external/maverick/IRouter.sol";
import { IReward } from "src/tokemak/interfaces/external/maverick/IReward.sol";
import { IPosition } from "src/tokemak/interfaces/external/maverick/IPosition.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IPoolPositionSlim } from "src/tokemak/interfaces/external/maverick/IPoolPositionSlim.sol";
import { MaverickStakingAdapter } from "src/tokemak/destinations/adapters/staking/MaverickStakingAdapter.sol";
import { MaverickRewardsAdapter } from "src/tokemak/destinations/adapters/rewards/MaverickRewardsAdapter.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IncentiveCalculatorBase } from "src/tokemak/stats/calculators/base/IncentiveCalculatorBase.sol";

contract MaverickDestinationVault is DestinationVault {
    error NothingToClaim();
    error NoDebtReclaimed();

    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Maverick swap and liquidity router
        address maverickRouter;
        /// @notice Maverick Boosted Position contract
        address maverickBoostedPosition;
        /// @notice Rewarder contract for the Boosted Position
        address maverickRewarder;
        /// @notice Pool that the Boosted Position proxies
        address maverickPool;
    }

    string private constant EXCHANGE_NAME = "maverick";

    /// @dev Tokens that make up the pool
    address[] private constituentTokens;

    /// @notice Maverick swap and liquidity router
    IRouter public maverickRouter;

    /// @notice Maverick Boosted Position contract
    IPoolPositionSlim public maverickBoostedPosition;

    /// @notice Rewarder contract for the Boosted Position
    IReward public maverickRewarder;

    /// @notice Pool that the Boosted Position proxies
    IPool public maverickPool;

    /// @notice Address Mavericks Position NFT
    IPosition public positionNft;

    constructor(
        ISystemRegistry sysRegistry
    ) DestinationVault(sysRegistry) { }

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

        Errors.verifyNotZero(initParams.maverickRouter, "maverickRouter");
        Errors.verifyNotZero(initParams.maverickBoostedPosition, "maverickBoostedPosition");
        Errors.verifyNotZero(initParams.maverickRewarder, "maverickRewarder");
        Errors.verifyNotZero(initParams.maverickPool, "maverickPool");

        maverickRouter = IRouter(initParams.maverickRouter);
        maverickBoostedPosition = IPoolPositionSlim(initParams.maverickBoostedPosition);
        maverickRewarder = IReward(initParams.maverickRewarder);
        maverickPool = IPool(initParams.maverickPool);

        // Base class has the initializer() modifier to prevent double-setup
        // If you don't call the base initialize, make sure you protect this call
        super.initialize(baseAsset_, underlyer_, rewarder_, incentiveCalculator_, additionalTrackedTokens_, params_);

        positionNft = IRouter(initParams.maverickRouter).position();
        address stakingToken = IReward(initParams.maverickRewarder).stakingToken();

        if (address(stakingToken) != address(_underlying)) {
            revert Errors.InvalidConfiguration();
        }

        address tokenA = address(IPool(initParams.maverickPool).tokenA());
        address tokenB = address(IPool(initParams.maverickPool).tokenB());
        _addTrackedToken(tokenA);
        _addTrackedToken(tokenB);

        constituentTokens = new address[](2);
        constituentTokens[0] = tokenA;
        constituentTokens[1] = tokenB;
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

    /// @notice Get the balance of underlyer currently staked in Maverick Rewarder
    /// @return Balance of underlyer currently staked in Maverick Rewarder
    function externalQueriedBalance() public view override returns (uint256) {
        return maverickRewarder.balanceOf(address(this));
    }

    /// @inheritdoc IDestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc IDestinationVault
    function poolType() external pure override returns (string memory) {
        return "maverick";
    }

    /// @inheritdoc IDestinationVault
    /// @notice This contract do not support ETH pool
    function poolDealInEth() external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IDestinationVault
    function underlyingTotalSupply() external view virtual override returns (uint256) {
        return IERC20(_underlying).totalSupply();
    }

    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view override returns (address[] memory result) {
        result = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            result[i] = constituentTokens[i];
        }
    }

    /// @inheritdoc IDestinationVault
    function underlyingReserves() external view override returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](2);
        tokens[0] = constituentTokens[0];
        tokens[1] = constituentTokens[1];

        //slither-disable-next-line similar-names
        (uint256 reserveTokenA, uint256 reserveTokenB) = maverickBoostedPosition.getReserves();

        amounts = new uint256[](2);
        amounts[0] = reserveTokenA;
        amounts[1] = reserveTokenB;
    }

    /// @notice Callback during a deposit after the sender has been minted shares (if applicable)
    /// @dev Should be used for staking tokens into protocols, etc
    /// @param amount underlying tokens received
    function _onDeposit(
        uint256 amount
    ) internal virtual override {
        MaverickStakingAdapter.stakeLPs(maverickRewarder, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(
        uint256 amount
    ) internal virtual override {
        MaverickStakingAdapter.unstakeLPs(maverickRewarder, amount);
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) = MaverickRewardsAdapter.claimRewards(address(maverickRewarder), msg.sender);
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(
        uint256 underlyerAmount
    ) internal virtual override returns (address[] memory tokens, uint256[] memory amounts) {
        //slither-disable-start similar-names
        (uint256 sellAmountA, uint256 sellAmountB) =
            maverickBoostedPosition.burnFromToAddressAsReserves(address(this), address(this), underlyerAmount);

        tokens = new address[](2);
        amounts = new uint256[](2);

        tokens[0] = constituentTokens[0];
        tokens[1] = constituentTokens[1];

        amounts[0] = sellAmountA;
        amounts[1] = sellAmountB;
        //slither-disable-end similar-names
    }

    /// @inheritdoc DestinationVault
    function getPool() public view override returns (address) {
        return address(maverickPool);
    }

    function _validateCalculator(
        address incentiveCalculator
    ) internal view override {
        address calcLp = IncentiveCalculatorBase(incentiveCalculator).lpToken();
        address calcPool = IncentiveCalculatorBase(incentiveCalculator).pool();

        if (calcLp != _underlying) {
            revert InvalidIncentiveCalculator(calcLp, _underlying, "lp");
        }
        if (calcPool != address(maverickPool)) {
            revert InvalidIncentiveCalculator(calcPool, address(maverickPool), "pool");
        }
    }
}
