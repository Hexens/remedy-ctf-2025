// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { IAutopilotRouterBase } from "src/tokemak/interfaces/vault/IAutopilotRouterBase.sol";
import { IRewards } from "src/tokemak/interfaces/rewarders/IRewards.sol";
import { SwapParams } from "src/tokemak/interfaces/liquidation/IAsyncSwapper.sol";
import { ISwapRouterV2 } from "src/tokemak/interfaces/swapper/ISwapRouterV2.sol";

/**
 * @title IAutopilotRouter Interface
 * @notice Extends the IAutopilotRouterBase with specific flows to save gas
 */
interface IAutopilotRouter is IAutopilotRouterBase {
    /**
     * ***************************   Deposit ********************************
     */

    /**
     * @notice deposit available asset balance to a AutopoolETH.
     * @param vault The AutopoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param minSharesOut The min amount of `vault` shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinSharesError
     */
    function depositBalance(
        IAutopool vault,
        address to,
        uint256 minSharesOut
    ) external payable returns (uint256 sharesOut);

    /**
     * @notice deposit max assets to a AutopoolETH.
     * @param vault The AutopoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param minSharesOut The min amount of `vault` shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinSharesError
     */
    function depositMax(
        IAutopool vault,
        address to,
        uint256 minSharesOut
    ) external payable returns (uint256 sharesOut);

    /**
     * *************************   Withdraw   **********************************
     */

    /**
     * @notice withdraw `amount` to a AutopoolETH.
     * @param fromVault The AutopoolETH to withdraw assets from.
     * @param toVault The AutopoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param amount The amount of assets to withdraw from fromVault.
     * @param maxSharesIn The max amount of fromVault shares withdrawn by caller.
     * @param minSharesOut The min amount of toVault shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MaxSharesError, MinSharesError
     */
    function withdrawToDeposit(
        IAutopool fromVault,
        IAutopool toVault,
        address to,
        uint256 amount,
        uint256 maxSharesIn,
        uint256 minSharesOut
    ) external payable returns (uint256 sharesOut);

    /**
     * *************************   Redeem    ********************************
     */

    /**
     * @notice redeem `shares` to a AutopoolETH.
     * @param fromVault The AutopoolETH to redeem shares from.
     * @param toVault The AutopoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param shares The amount of shares to redeem from fromVault.
     * @param minSharesOut The min amount of toVault shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinAmountError, MinSharesError
     */
    function redeemToDeposit(
        IAutopool fromVault,
        IAutopool toVault,
        address to,
        uint256 shares,
        uint256 minSharesOut
    ) external payable returns (uint256 sharesOut);

    /**
     * @notice redeem max shares to a AutopoolETH.
     * @param vault The AutopoolETH to redeem shares from.
     * @param to The destination of assets.
     * @param minAmountOut The min amount of assets received by `to`.
     * @return amountOut the amount of assets received by `to`.
     * @dev throws MinAmountError
     */
    function redeemMax(
        IAutopool vault,
        address to,
        uint256 minAmountOut
    ) external payable returns (uint256 amountOut);

    /**
     * @notice redeem `shares` shares from a AutopoolETH with a custom route
     * @param vault The AutopoolETH to redeem shares from.
     * @param to The destination of assets.
     * @param shares The amount of shares to redeem from vault.
     * @param minAmountOut The min amount of assets received by `to`.
     * @param customRoute The custom route to use for the swap.
     * @return amountOut the amount of assets received by `to`.
     * @dev throws MinAmountError
     */
    function redeemWithRoutes(
        IAutopool vault,
        address to,
        uint256 shares,
        uint256 minAmountOut,
        ISwapRouterV2.UserSwapData[] calldata customRoute
    ) external payable returns (uint256 amountOut);

    /**
     * @notice swaps token
     * @param swapper Address of the swapper to use
     * @param swapParams  Parameters for the swap
     * @return amountReceived Swap output amount
     */
    function swapToken(
        address swapper,
        SwapParams memory swapParams
    ) external payable returns (uint256 amountReceived);

    /**
     * @notice claims vault token rewards
     * @param rewarder Address of the rewarder to claim from
     * @param recipient Struct containing recipient details
     * @return amountReceived Swap output amount
     */
    function claimRewards(
        IRewards rewarder,
        IRewards.Recipient calldata recipient,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable returns (uint256);

    /**
     * @notice swaps Exact token balance in the contract
     * @param swapper Address of the swapper to use
     * @param swapParams  Parameters for the swap
     * @return amountReceived Swap output amount
     * @dev sets the sellAmount to the balance of the contract
     */
    function swapTokenBalance(
        address swapper,
        SwapParams memory swapParams
    ) external payable returns (uint256 amountReceived);

    /**
     * @notice stake Acc token balance
     * @param duration The duration of the stake
     * @param accToke contract address of the AccToke
     * @param to The destination of ownership shares.
     */
    function stakeAccBalance(address accToke, uint256 duration, address to) external payable;

    /**
     * @notice stake Acc token for specified amount
     * @param amount Amount of TOKE to stake
     * @param accToke contract address of the AccToke
     * @param duration The duration of the stake
     * @param to The destination of ownership shares.
     */
    function stakeAcc(address accToke, uint256 amount, uint256 duration, address to) external payable;

    /**
     * @notice unstake Acc token balance
     * @param accToke contract address of the AccToke
     * @param lockupIds The lockup ids to unstake
     * @param to The destination of staked TOKE.
     */
    function unstakeAcc(address accToke, uint256[] memory lockupIds, address to) external payable;

    /**
     * @notice Collect staking rewards
     * @dev rewards can only be sent to user or router
     * @param accToke contract address of the AccToke
     * @param recipient The recipient of the rewards
     * @return amountReceived Swap output amount
     */
    function collectAccTokeRewards(address accToke, address recipient) external payable returns (uint256);
}
