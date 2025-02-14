// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title AutopoolETH Router Base Interface
 * @notice A canonical router between AutopoolETHs
 *
 * The base router is a multicall style router inspired by Uniswap v3 with built-in features for permit,
 * WETH9 wrap/unwrap, and ERC20 token pulling/sweeping/approving. It includes methods for the four mutable
 * ERC4626 functions deposit/mint/withdraw/redeem as well.
 *
 * These can all be arbitrarily composed using the multicall functionality of the router.
 *
 * NOTE the router is capable of pulling any approved token from your wallet. This is only possible when
 * your address is msg.sender, but regardless be careful when interacting with the router or ERC4626 Vaults.
 * The router makes no special considerations for unique ERC20 implementations such as fee on transfer.
 * There are no built in protections for unexpected behavior beyond enforcing the minSharesOut is received.
 */
interface IAutopilotRouterBase {
    /// @notice thrown when amount of assets received is below the min set by caller
    error MinAmountError();

    /// @notice thrown when amount of shares received is below the min set by caller
    error MinSharesError();

    /// @notice thrown when amount of assets received is above the max set by caller
    error MaxAmountError();

    /// @notice thrown when amount of shares received is above the max set by caller
    error MaxSharesError();

    /// @notice thrown when timestamp is too old
    error TimestampTooOld();

    /**
     * @notice mint `shares` from an ERC4626 vault.
     * @param vault The AutopoolETH to mint shares from.
     * @param to The destination of ownership shares.
     * @param shares The amount of shares to mint from `vault`.
     * @param maxAmountIn The max amount of assets used to mint.
     * @return amountIn the amount of assets used to mint by `to`.
     * @dev throws MaxAmountError
     */
    function mint(
        IAutopool vault,
        address to,
        uint256 shares,
        uint256 maxAmountIn
    ) external payable returns (uint256 amountIn);

    /**
     * @notice deposit `amount` to an ERC4626 vault.
     * @param vault The AutopoolETH to deposit assets to.
     * @param to The destination of ownership shares.
     * @param amount The amount of assets to deposit to `vault`.
     * @param minSharesOut The min amount of `vault` shares received by `to`.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MinSharesError
     */
    function deposit(
        IAutopool vault,
        address to,
        uint256 amount,
        uint256 minSharesOut
    ) external payable returns (uint256 sharesOut);

    /**
     * @notice withdraw `amount` from an ERC4626 vault.
     * @param vault The AutopoolETH to withdraw assets from.
     * @param to The destination of assets.
     * @param amount The amount of assets to withdraw from vault.
     * @param maxSharesOut The max amount of shares burned for assets requested.
     * @return sharesOut the amount of shares received by `to`.
     * @dev throws MaxSharesError
     */
    function withdraw(
        IAutopool vault,
        address to,
        uint256 amount,
        uint256 maxSharesOut
    ) external payable returns (uint256 sharesOut);

    /**
     * @notice redeem `shares` shares from a AutopoolETH
     * @param vault The AutopoolETH to redeem shares from.
     * @param to The destination of assets.
     * @param shares The amount of shares to redeem from vault.
     * @param minAmountOut The min amount of assets received by `to`.
     * @return amountOut the amount of assets received by `to`.
     * @dev throws MinAmountError
     */
    function redeem(
        IAutopool vault,
        address to,
        uint256 shares,
        uint256 minAmountOut
    ) external payable returns (uint256 amountOut);

    /// @notice Stakes vault token to corresponding rewarder.
    /// @param vault IERC20 instance of an Autopool to stake to.
    /// @param maxAmount Maximum amount for user to stake.  Amount > balanceOf(user) will stake all present tokens.
    /// @return staked Returns total amount staked.
    function stakeVaultToken(IERC20 vault, uint256 maxAmount) external payable returns (uint256 staked);

    /// @notice Unstakes vault token from corresponding rewarder.
    /// @param vault IAutopool instance of the vault token to withdraw.
    /// @param rewarder Rewarder to withdraw from.
    /// @param maxAmount Amount of vault token to withdraw Amount > balanceOf(user) will withdraw all owned tokens.
    /// @param claim Claiming rewards or not on unstaking.
    /// @return withdrawn Amount of vault token withdrawn.
    function withdrawVaultToken(
        IAutopool vault,
        IMainRewarder rewarder,
        uint256 maxAmount,
        bool claim
    ) external payable returns (uint256 withdrawn);

    /// @notice Claims rewards on user stake of vault token.
    /// @param vault IAutopool instance of vault token to claim rewards for.
    /// @param rewarder Rewarder to claim rewards from.
    /// @param recipient Address to claim rewards for.
    function claimAutopoolRewards(IAutopool vault, IMainRewarder rewarder, address recipient) external payable;

    /// @notice Checks if timestamp is expired. Purpose is to check the execution deadline with the multicall.
    /// @param timestamp Timestamp to check.
    /// @dev throws TimestampTooOld. Payable to allow for multicall.
    function expiration(
        uint256 timestamp
    ) external payable;
}
