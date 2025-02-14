// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { SwapParams } from "src/tokemak/interfaces/liquidation/IAsyncSwapper.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";

interface ILiquidationRow {
    event SwapperAdded(address indexed swapper);
    event SwapperRemoved(address indexed swapper);
    event FeeReceiverSet(address indexed feeReceiver, uint256 feeBps);
    event BalanceUpdated(address indexed token, address indexed vault, uint256 balance);
    event VaultLiquidated(address indexed vault, address indexed fromToken, address indexed toToken, uint256 amount);
    event GasUsedForVault(address indexed vault, uint256 gasAmount, bytes32 action);
    event FeesTransferred(address indexed receiver, uint256 amountReceived, uint256 fees);
    event PriceMarginSet(uint256 priceMarginBps);

    error NothingToLiquidate();
    error InvalidRewardToken();
    error FeeTooHigh();
    error SellAmountMismatch(uint256 totalBalanceToLiquidate, uint256 buyAmount);
    error AmountsMismatch(uint256 sellAmount, uint256 buyAmount);
    error InsufficientAmountReceived(uint256 expectedAmount, uint256 amountReceived);
    error DeadlineExceeded(uint256 deadline, uint256 currentTimestamp);

    /**
     * @param fromToken The address of the token to be liquidated
     * @param asyncSwapper The address of the async swapper
     * @param vaultsToLiquidate An array of vault addresses to liquidate
     * @param params Swap parameters for the async swapper
     */
    struct LiquidationParams {
        address fromToken;
        address asyncSwapper;
        IDestinationVault[] vaultsToLiquidate;
        SwapParams param;
    }

    /**
     * @notice Claim rewards from a list of vaults
     * @param vaults The list of vaults to claim rewards from
     */
    function claimsVaultRewards(
        IDestinationVault[] memory vaults
    ) external;

    /**
     * @notice Add a new swapper to the whitelist
     * @param swapper The address of the swapper to be added
     */
    function addToWhitelist(
        address swapper
    ) external;

    /**
     * @notice Remove a swapper from whitelist
     * @param swapper The address of the swapper to be removed
     */
    function removeFromWhitelist(
        address swapper
    ) external;

    /**
     * @notice Check if a swapper is whitelisted
     * @param swapper The address of the swapper to be checked
     * @return true if the swapper is allowed
     */
    function isWhitelisted(
        address swapper
    ) external view returns (bool);

    /**
     * @notice Sets the fee and the receiver of the fee.
     *  If either _feeReceiver is address(0) or _feeBps is 0, the fee feature is turned off.
     * @dev FeeBps must be less than or equal to 5_000, i.e., 50%.
     * @param _feeReceiver The address of the fee receiver. If set to address(0), the fee feature is turned off.
     * @param _feeBps The fee rate in basis points (bps). 1 bps is 0.01%. If set to 0, the fee feature is turned off.
     */
    function setFeeAndReceiver(address _feeReceiver, uint256 _feeBps) external;

    /**
     * @notice Sets the price margin in bps for swap validation
     * @param _priceMarginBps The price margin in basis points (bps)
     */
    function setPriceMarginBps(
        uint256 _priceMarginBps
    ) external;

    /**
     * @notice Get the balance of a specific token and vault
     * @param tokenAddress The address of the token
     * @param vaultAddress The address of the vault
     * @return The balance of the specific token and vault
     */
    function balanceOf(address tokenAddress, address vaultAddress) external view returns (uint256);

    /**
     * @notice Get the total balance of a specific token across all vaults
     * @param tokenAddress The address of the token
     * @return The total balance of the specific token across all vaults
     */
    function totalBalanceOf(
        address tokenAddress
    ) external view returns (uint256);

    /**
     * @notice Get the list of reward tokens
     * @return An array containing the addresses of reward tokens
     */
    function getTokens() external view returns (address[] memory);

    /**
     * @notice Get the list of vaults associated with a specific token
     * @param tokenAddress The address of the token
     * @return An array of vault addresses associated with the given token
     */
    function getVaultsForToken(
        address tokenAddress
    ) external view returns (address[] memory);

    /**
     * @notice Conducts the liquidation process for a specific token across a list of vaults,
     * performing the necessary balance adjustments, initiating the swap process via the asyncSwapper,
     * using the price oracle for a fair swap validation, taking a fee from the received amount, and queues the
     * remaining swapped tokens in the MainRewarder associated with each vault.
     * @param liquidationParams A LiquidationParams struct containing the necessary parameters for liquidation
     */
    function liquidateVaultsForToken(
        LiquidationParams memory liquidationParams
    ) external;

    /**
     * @notice Same logic as liquidateVaultsForToken but for multiple tokens
     * @param liquidationParams An array of LiquidationParams structs containing the necessary parameters for
     * liquidation
     */
    function liquidateVaultsForTokens(
        LiquidationParams[] memory liquidationParams
    ) external;
}
