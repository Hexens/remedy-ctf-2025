// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { AutopoolFees } from "src/tokemak/vault/libs/AutopoolFees.sol";
import { AutopoolToken } from "src/tokemak/vault/libs/AutopoolToken.sol";
import { AutopoolDebt } from "src/tokemak/vault/libs/AutopoolDebt.sol";
import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { StructuredLinkedList } from "src/tokemak/strategy/StructuredLinkedList.sol";
import { WithdrawalQueue } from "src/tokemak/strategy/WithdrawalQueue.sol";

library Autopool4626 {
    using SafeERC20 for IERC20Metadata;
    using WithdrawalQueue for StructuredLinkedList.List;
    using AutopoolToken for AutopoolToken.TokenData;

    /// =====================================================
    /// Errors
    /// =====================================================

    error InvalidTotalAssetPurpose();

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Nav(uint256 idle, uint256 debt, uint256 totalSupply);
    event TokensRecovered(address[] tokens, uint256[] amounts, address[] destinations);

    /// @notice Returns the amount of tokens owned by account.
    /// @dev Subtracts any unlocked profit shares that will be burned when account is the Vault itself
    function balanceOf(
        AutopoolToken.TokenData storage tokenData,
        IAutopool.ProfitUnlockSettings storage profitUnlockSettings,
        address account
    ) public view returns (uint256) {
        if (account == address(this)) {
            return tokenData.balances[account] - AutopoolFees.unlockedShares(profitUnlockSettings, tokenData);
        }
        return tokenData.balances[account];
    }

    /// @notice Returns the total amount of the underlying asset that is “managed” by Vault.
    /// @dev Utilizes the "Global" purpose internally
    function totalAssets(
        IAutopool.AssetBreakdown storage assetBreakdown
    ) public view returns (uint256) {
        return totalAssets(assetBreakdown, IAutopool.TotalAssetPurpose.Global);
    }

    /// @notice Returns the total amount of the underlying asset that is “managed” by the Vault with respect to its
    /// usage
    /// @dev Value changes based on purpose. Global is an avg. Deposit is valued higher. Withdraw is valued lower.
    /// @param purpose The calculation the total assets will be used in
    function totalAssets(
        IAutopool.AssetBreakdown storage assetBreakdown,
        IAutopool.TotalAssetPurpose purpose
    ) public view returns (uint256) {
        if (purpose == IAutopool.TotalAssetPurpose.Global) {
            return assetBreakdown.totalIdle + assetBreakdown.totalDebt;
        } else if (purpose == IAutopool.TotalAssetPurpose.Deposit) {
            return assetBreakdown.totalIdle + assetBreakdown.totalDebtMax;
        } else if (purpose == IAutopool.TotalAssetPurpose.Withdraw) {
            return assetBreakdown.totalIdle + assetBreakdown.totalDebtMin;
        } else {
            revert InvalidTotalAssetPurpose();
        }
    }

    function maxMint(
        AutopoolToken.TokenData storage tokenData,
        IAutopool.ProfitUnlockSettings storage profitUnlockSettings,
        StructuredLinkedList.List storage debtReportQueue,
        mapping(address => AutopoolDebt.DestinationInfo) storage destinationInfo,
        address,
        bool paused,
        bool shutdown
    ) public returns (uint256) {
        // If we are temporarily paused, or in full shutdown mode,
        // no new shares are able to be minted
        if (paused || shutdown) {
            return 0;
        }

        // First deposit
        uint256 ts = totalSupply(tokenData, profitUnlockSettings);
        if (ts == 0) {
            return type(uint112).max;
        }

        // We know totalSupply greater than zero now so if totalAssets is zero
        // the vault is in an invalid state and users would be able to mint shares for free
        uint256 ta =
            AutopoolDebt.totalAssetsTimeChecked(debtReportQueue, destinationInfo, IAutopool.TotalAssetPurpose.Deposit);
        if (ta == 0) {
            return 0;
        }

        if (ts > type(uint112).max) {
            return 0;
        }

        return type(uint112).max - ts;
    }

    /// @notice Returns the amount of tokens in existence.
    /// @dev Subtracts any unlocked profit shares that will be burned
    function totalSupply(
        AutopoolToken.TokenData storage tokenData,
        IAutopool.ProfitUnlockSettings storage profitUnlockSettings
    ) public view returns (uint256 shares) {
        shares = tokenData.totalSupply - AutopoolFees.unlockedShares(profitUnlockSettings, tokenData);
    }

    function transferAndMint(
        IERC20Metadata baseAsset,
        IAutopool.AssetBreakdown storage assetBreakdown,
        AutopoolToken.TokenData storage tokenData,
        IAutopool.ProfitUnlockSettings storage profitUnlockSettings,
        uint256 assets,
        uint256 shares,
        address receiver
    ) public {
        // From OZ documentation:
        // ----------------------
        // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth

        baseAsset.safeTransferFrom(msg.sender, address(this), assets);

        assetBreakdown.totalIdle += assets;

        tokenData.mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        emit Nav(assetBreakdown.totalIdle, assetBreakdown.totalDebt, totalSupply(tokenData, profitUnlockSettings));
    }

    /// @notice Transfer out non-tracked tokens
    function recover(address[] calldata tokens, uint256[] calldata amounts, address[] calldata destinations) external {
        // Makes sure our params are valid
        uint256 len = tokens.length;

        Errors.verifyNotZero(len, "len");
        Errors.verifyArrayLengths(len, amounts.length, "tokens+amounts");
        Errors.verifyArrayLengths(len, destinations.length, "tokens+destinations");

        emit TokensRecovered(tokens, amounts, destinations);

        //IAutopool autoPool = IAutopool(address(this));

        for (uint256 i = 0; i < len; ++i) {
            (address tokenAddress, uint256 amount, address destination) = (tokens[i], amounts[i], destinations[i]);

            // Ensure this isn't an asset we care about
            // if (
            //     tokenAddress == address(this) || tokenAddress == autoPool.asset()
            //         || autoPool.isDestinationRegistered(tokenAddress)
            //         || autoPool.isDestinationQueuedForRemoval(tokenAddress)
            // ) {
            //     revert Errors.AssetNotAllowed(tokenAddress);
            // }

            if (tokenAddress != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                IERC20Metadata(tokenAddress).safeTransfer(destination, amount);
            } else {
                // solhint-disable-next-line avoid-low-level-calls
                payable(destination).call{ value: amount };
            }
        }
    }
}
