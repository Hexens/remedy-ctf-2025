// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { AutopoolDebt } from "src/tokemak/vault/libs/AutopoolDebt.sol";
import { IERC4626 } from "src/tokemak/interfaces/vault/IERC4626.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IAutopool is IERC4626, IERC20Permit {
    enum VaultShutdownStatus {
        Active,
        Deprecated,
        Exploit
    }

    /// @param unlockPeriodInSeconds Time it takes for profit to unlock in seconds
    /// @param fullProfitUnlockTime Time at which all profit will have been unlocked
    /// @param lastProfitUnlockTime Last time profits were unlocked
    /// @param profitUnlockRate Per second rate at which profit shares unlocks. Rate when calculated is denominated in
    /// MAX_BPS_PROFIT. TODO: Get into uint112
    struct ProfitUnlockSettings {
        uint48 unlockPeriodInSeconds;
        uint48 fullProfitUnlockTime;
        uint48 lastProfitUnlockTime;
        uint256 profitUnlockRate;
    }

    /// @param feeSink Where claimed fees are sent
    /// @param totalAssetsHighMark The last totalAssets amount we took fees at
    /// @param totalAssetsHighMarkTimestamp The last timestamp we updated the high water mark
    /// @param lastPeriodicFeeTake Timestamp of when the last periodic fee was taken.
    /// @param periodicFeeSink Address that receives periodic fee.
    /// @param periodicFeeBps Current periodic fee.  100% == 10000.
    /// @param streamingFeeBps Current streaming fee taken on profit. 100% == 10000
    /// @param navPerShareLastFeeMark The last nav/share height we took fees at
    /// @param navPerShareLastFeeMarkTimestamp The last timestamp we took fees at
    /// @param rebalanceFeeHighWaterMarkEnabled Returns whether the nav/share high water mark is enabled for the
    /// rebalance fee
    struct AutopoolFeeSettings {
        address feeSink;
        uint256 totalAssetsHighMark;
        uint256 totalAssetsHighMarkTimestamp;
        uint256 lastPeriodicFeeTake;
        address periodicFeeSink;
        uint256 periodicFeeBps;
        uint256 streamingFeeBps;
        uint256 navPerShareLastFeeMark;
        uint256 navPerShareLastFeeMarkTimestamp;
        bool rebalanceFeeHighWaterMarkEnabled;
    }

    /// @param totalIdle The amount of baseAsset deposited into the contract pending deployment
    /// @param totalDebt The current (though cached) value of assets we've deployed
    /// @param totalDebtMin The current (though cached) value of assets we use for valuing during deposits
    /// @param totalDebtMax The current (though cached) value of assets we use for valuing during withdrawals
    struct AssetBreakdown {
        uint256 totalIdle;
        uint256 totalDebt;
        uint256 totalDebtMin;
        uint256 totalDebtMax;
    }

    enum TotalAssetPurpose {
        Global,
        Deposit,
        Withdraw
    }

    /* ******************************** */
    /*      Events                      */
    /* ******************************** */
    event TokensPulled(address[] tokens, uint256[] amounts, address[] destinations);
    event TokensRecovered(address[] tokens, uint256[] amounts, address[] destinations);
    event Nav(uint256 idle, uint256 debt, uint256 totalSupply);
    event RewarderSet(address newRewarder, address oldRewarder);
    event DestinationDebtReporting(address destination, uint256 debtValue, uint256 claimed, uint256 claimGasUsed);
    event FeeCollected(uint256 fees, address feeSink, uint256 mintedShares, uint256 profit, uint256 idle, uint256 debt);
    event PeriodicFeeCollected(uint256 fees, address feeSink, uint256 mintedShares);
    event Shutdown(VaultShutdownStatus reason);

    /* ******************************** */
    /*      Errors                      */
    /* ******************************** */

    error ERC4626MintExceedsMax(uint256 shares, uint256 maxMint);
    error ERC4626DepositExceedsMax(uint256 assets, uint256 maxDeposit);
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);
    error InvalidShutdownStatus(VaultShutdownStatus status);

    error WithdrawalFailed();
    error DepositFailed();
    error InsufficientFundsInDestinations(uint256 deficit);
    error WithdrawalIncomplete();
    error ValueSharesMismatch(uint256 value, uint256 shares);

    /// @notice A full unit of this pool
    // solhint-disable-next-line func-name-mixedcase
    function ONE() external view returns (uint256);

    /// @notice Query the type of vault
    function vaultType() external view returns (bytes32);

    /// @notice Strategy governing the pools rebalances
    function autoPoolStrategy() external view returns (IAutopoolStrategy);

    /// @notice Allow token recoverer to collect dust / unintended transfers (non-tracked assets only)
    function recover(address[] calldata tokens, uint256[] calldata amounts, address[] calldata destinations) external;

    /// @notice Set the order of destination vaults used for withdrawals
    // NOTE: will be done going directly to strategy (IStrategy) vault points to.
    //       How it'll delegate is still being decided
    // function setWithdrawalQueue(address[] calldata destinations) external;

    /// @notice Get a list of destination vaults with pending assets to clear out
    function getRemovalQueue() external view returns (address[] memory);

    function getFeeSettings() external view returns (AutopoolFeeSettings memory);

    /// @notice Initiate the shutdown procedures for this vault
    function shutdown(
        VaultShutdownStatus reason
    ) external;

    /// @notice True if the vault has been shutdown
    function isShutdown() external view returns (bool);

    /// @notice Returns the reason for shutdown (or `Active` if not shutdown)
    function shutdownStatus() external view returns (VaultShutdownStatus);

    /// @notice gets the list of supported destination vaults for the Autopool/Strategy
    /// @return _destinations List of supported destination vaults
    function getDestinations() external view returns (address[] memory _destinations);

    function convertToShares(
        uint256 assets,
        uint256 totalAssetsForPurpose,
        uint256 supply,
        Math.Rounding rounding
    ) external view returns (uint256 shares);

    function convertToAssets(
        uint256 shares,
        uint256 totalAssetsForPurpose,
        uint256 supply,
        Math.Rounding rounding
    ) external view returns (uint256 assets);

    function totalAssets(
        TotalAssetPurpose purpose
    ) external view returns (uint256);

    function getAssetBreakdown() external view returns (AssetBreakdown memory);

    /// @notice get a destinations last reported debt value
    /// @param destVault the address of the target destination
    /// @return destinations last reported debt value
    function getDestinationInfo(
        address destVault
    ) external view returns (AutopoolDebt.DestinationInfo memory);

    /// @notice check if a destination is registered with the vault
    function isDestinationRegistered(
        address destination
    ) external view returns (bool);

    /// @notice get if a destinationVault is queued for removal by the AutopoolETH
    function isDestinationQueuedForRemoval(
        address destination
    ) external view returns (bool);

    /// @notice Returns instance of vault rewarder.
    function rewarder() external view returns (IMainRewarder);

    /// @notice Returns all past rewarders.
    function getPastRewarders() external view returns (address[] memory _pastRewarders);

    /// @notice Returns boolean telling whether address passed in is past rewarder.
    function isPastRewarder(
        address _pastRewarder
    ) external view returns (bool);
}
