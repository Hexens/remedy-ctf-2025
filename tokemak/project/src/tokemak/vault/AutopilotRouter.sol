// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { IAutopool, IAutopilotRouter } from "src/tokemak/interfaces/vault/IAutopilotRouter.sol";
import { IAccToke } from "src/tokemak/interfaces/staking/IAccToke.sol";
import { IRewards } from "src/tokemak/interfaces/rewarders/IRewards.sol";
import { SwapParams, IAsyncSwapper } from "src/tokemak/interfaces/liquidation/IAsyncSwapper.sol";
import { ISwapRouterV2 } from "src/tokemak/interfaces/swapper/ISwapRouterV2.sol";
import { ISystemSecurity } from "src/tokemak/interfaces/security/ISystemSecurity.sol";
import { AutopilotRouterBase, ISystemRegistry } from "src/tokemak/vault/AutopilotRouterBase.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ContractTypes } from "src/tokemak/libs/ContractTypes.sol";

/// @title ERC4626Router contract
contract AutopilotRouter is IAutopilotRouter, AutopilotRouterBase, ReentrancyGuard {
    using Address for address;

    constructor(
        ISystemRegistry _systemRegistry
    ) AutopilotRouterBase(_systemRegistry) { }

    // For the below, no approval needed, assumes vault is already max approved

    /// @inheritdoc IAutopilotRouter
    function withdrawToDeposit(
        IAutopool fromVault,
        IAutopool toVault,
        address to,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) external payable override returns (uint256 sharesOut) {
        withdraw(fromVault, address(this), amount, maxSharesIn);
        approve(IERC20(toVault.asset()), address(toVault), amount);
        return deposit(toVault, to, amount, minSharesOut);
    }

    /// @inheritdoc IAutopilotRouter
    function redeemToDeposit(
        IAutopool fromVault,
        IAutopool toVault,
        address to,
        uint256 shares,
        uint256 minSharesOut
    ) external payable override returns (uint256 sharesOut) {
        // amount out passes through so only one slippage check is needed
        uint256 amount = redeem(fromVault, address(this), shares, 0);

        approve(IERC20(toVault.asset()), address(toVault), amount);
        return deposit(toVault, to, amount, minSharesOut);
    }

    /// @inheritdoc IAutopilotRouter
    function swapToken(
        address swapper,
        SwapParams memory swapParams
    ) external payable nonReentrant returns (uint256 amountReceived) {
        systemRegistry.asyncSwapperRegistry().verifyIsRegistered(swapper);

        bytes memory data = swapper.functionDelegateCall(abi.encodeCall(IAsyncSwapper.swap, swapParams), "SwapFailed");

        amountReceived = abi.decode(data, (uint256));
    }

    /// @inheritdoc IAutopilotRouter
    function swapTokenBalance(
        address swapper,
        SwapParams memory swapParams
    ) external payable nonReentrant returns (uint256 amountReceived) {
        systemRegistry.asyncSwapperRegistry().verifyIsRegistered(swapper);

        IERC20 sellToken = IERC20(swapParams.sellTokenAddress);
        swapParams.sellAmount = sellToken.balanceOf(address(this));

        bytes memory data = swapper.functionDelegateCall(abi.encodeCall(IAsyncSwapper.swap, swapParams), "SwapFailed");

        amountReceived = abi.decode(data, (uint256));
    }

    /// @inheritdoc IAutopilotRouter
    function depositBalance(
        IAutopool vault,
        address to,
        uint256 minSharesOut
    ) public payable override returns (uint256 sharesOut) {
        uint256 vaultAssetBalance = IERC20(vault.asset()).balanceOf(address(this));
        approve(IERC20(vault.asset()), address(vault), vaultAssetBalance);
        return deposit(vault, to, vaultAssetBalance, minSharesOut);
    }

    /// @inheritdoc IAutopilotRouter
    function depositMax(
        IAutopool vault,
        address to,
        uint256 minSharesOut
    ) public payable override returns (uint256 sharesOut) {
        IERC20 asset = IERC20(vault.asset());
        uint256 assetBalance = asset.balanceOf(msg.sender);
        uint256 maxDeposit = vault.maxDeposit(to);
        uint256 amount = maxDeposit < assetBalance ? maxDeposit : assetBalance;
        pullToken(asset, amount, address(this));

        approve(IERC20(vault.asset()), address(vault), amount);
        return deposit(vault, to, amount, minSharesOut);
    }

    /// @inheritdoc IAutopilotRouter
    function redeemMax(
        IAutopool vault,
        address to,
        uint256 minAmountOut
    ) public payable override returns (uint256 amountOut) {
        uint256 shareBalance = vault.balanceOf(msg.sender);
        uint256 maxRedeem = vault.maxRedeem(msg.sender);
        uint256 amountShares = maxRedeem < shareBalance ? maxRedeem : shareBalance;
        return redeem(vault, to, amountShares, minAmountOut);
    }

    function redeemWithRoutes(
        IAutopool vault,
        address to,
        uint256 shares,
        uint256 minAmountOut,
        ISwapRouterV2.UserSwapData[] calldata customRoutes
    ) public payable returns (uint256 amountOut) {
        if (!systemRegistry.autoPoolRegistry().isVault(address(vault))) {
            revert Errors.InvalidAddress(address(vault));
        }

        ISystemSecurity systemSecurity = systemRegistry.systemSecurity();
        systemSecurity.setAllowedAutopool(address(vault));

        ISwapRouterV2 swapRouter = ISwapRouterV2(payable(address(systemRegistry.swapRouter())));
        swapRouter.initTransientSwap(customRoutes);

        amountOut = redeem(vault, to, shares, minAmountOut);

        //clear the routes
        swapRouter.exitTransientSwap();
        systemSecurity.clearAllowedAutopool();

        return amountOut;
    }

    /// @inheritdoc IAutopilotRouter
    function claimRewards(
        IRewards rewarder,
        IRewards.Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable override returns (uint256) {
        if (msg.sender != recipient.wallet) revert Errors.AccessDenied();
        return rewarder.claimFor(recipient, v, r, s);
    }

    /// @inheritdoc IAutopilotRouter
    function stakeAccBalance(address accToke, uint256 duration, address to) public payable override {
        uint256 amount = IERC20(systemRegistry.toke()).balanceOf(address(this));
        return stakeAcc(accToke, amount, duration, to);
    }

    /// @inheritdoc IAutopilotRouter
    function stakeAcc(
        address accToke,
        uint256 amount,
        uint256 duration,
        address to
    ) public payable override validateAccToke(accToke) {
        approve(IERC20(systemRegistry.toke()), accToke, amount);
        return IAccToke(accToke).stake(amount, duration, to);
    }

    /// @inheritdoc IAutopilotRouter
    function unstakeAcc(
        address accToke,
        uint256[] memory lockupIds,
        address to
    ) public payable override validateAccToke(accToke) {
        IAccToke(accToke).unstake(lockupIds, msg.sender, to);
    }

    /// @inheritdoc IAutopilotRouter
    function collectAccTokeRewards(
        address accToke,
        address recipient
    ) public payable override validateAccToke(accToke) returns (uint256) {
        return IAccToke(accToke).collectRewards(msg.sender, recipient);
    }

    modifier validateAccToke(
        address accToke
    ) {
        if (!systemRegistry.isValidContract(ContractTypes.ACC_TOKE_INSTANCE, accToke)) {
            revert Errors.InvalidAddress(accToke);
        }
        _;
    }
}
