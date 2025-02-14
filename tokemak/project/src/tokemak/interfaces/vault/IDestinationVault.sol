// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseAssetVault } from "src/tokemak/interfaces/vault/IBaseAssetVault.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";

interface IDestinationVault is ISystemComponent, IBaseAssetVault, IERC20 {
    enum VaultShutdownStatus {
        Active,
        Deprecated,
        Exploit
    }

    error LogicDefect();
    error BaseAmountReceived(uint256 amount);

    /* ******************************** */
    /* View                             */
    /* ******************************** */

    /// @notice A full unit of this vault
    // solhint-disable-next-line func-name-mixedcase
    function ONE() external view returns (uint256);

    /// @notice The asset that is deposited into the vault
    function underlying() external view returns (address);

    /// @notice The total supply of the underlying asset
    function underlyingTotalSupply() external view returns (uint256);

    /// @notice The asset that rewards and withdrawals to the Autopool are denominated in
    /// @inheritdoc IBaseAssetVault
    function baseAsset() external view override returns (address);

    /// @notice Debt balance of underlying asset that is in contract.  This
    ///     value includes only assets that are known as debt by the rest of the
    ///     system (i.e. transferred in on rebalance), and does not include
    ///     extraneous amounts of underlyer that may have ended up in this contract.
    function internalDebtBalance() external view returns (uint256);

    /// @notice Debt balance of underlying asset staked externally.  This value only
    ///     includes assets known as debt to the rest of the system, and does not include
    ///     any assets staked on behalf of the DV in external contracts.
    function externalDebtBalance() external view returns (uint256);

    /// @notice Returns true value of _underlyer in DV.  Debt + tokens that may have
    ///     been transferred into the contract outside of rebalance.
    function internalQueriedBalance() external view returns (uint256);

    /// @notice Returns true value of staked _underlyer in external contract.  This
    ///     will include any _underlyer that has been staked on behalf of the DV.
    function externalQueriedBalance() external view returns (uint256);

    /// @notice Balance of underlying debt, sum of `externalDebtBalance()` and `internalDebtBalance()`.
    function balanceOfUnderlyingDebt() external view returns (uint256);

    /// @notice Rewarder for this vault
    function rewarder() external view returns (address);

    /// @notice Exchange this destination vault points to
    function exchangeName() external view returns (string memory);

    /// @notice The type of pool associated with this vault
    function poolType() external view returns (string memory);

    /// @notice If the pool only deals in ETH when adding or removing liquidity
    function poolDealInEth() external view returns (bool);

    /// @notice Tokens that base asset can be swapped into
    function underlyingTokens() external view returns (address[] memory);

    /// @notice Gets the reserves of the underlying tokens
    function underlyingReserves() external view returns (address[] memory tokens, uint256[] memory amounts);

    /* ******************************** */
    /* Events                           */
    /* ******************************** */

    event Donated(address sender, uint256 amount);
    event Withdraw(
        uint256 target, uint256 actual, uint256 debtLoss, uint256 claimLoss, uint256 fromIdle, uint256 fromDebt
    );
    event UpdateSignedMessage(bytes32 hash, bool flag);

    /* ******************************** */
    /* Errors                           */
    /* ******************************** */

    error ZeroAddress(string paramName);
    error InvalidShutdownStatus(VaultShutdownStatus status);

    /* ******************************** */
    /* Functions                        */
    /* ******************************** */

    /// @notice Setup the contract. These will be cloned so no constructor
    /// @param baseAsset_ Base asset of the system. WETH/USDC/etc
    /// @param underlyer_ Underlying asset the vault will wrap
    /// @param rewarder_ Reward tracker for this vault
    /// @param incentiveCalculator_ Incentive calculator for this vault
    /// @param additionalTrackedTokens_ Additional tokens that should be considered 'tracked'
    /// @param params_ Any extra parameters needed to setup the contract
    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) external;

    function getRangePricesLP() external returns (uint256 spotPrice, uint256 safePrice, bool isSpotSafe);

    /// @notice Calculates the current value of a portion of the debt based on shares
    /// @dev Queries the current value of all tokens we have deployed, whether its a single place, multiple, staked, etc
    /// @param shares The number of shares to value
    /// @return value The current value of our debt in terms of the baseAsset
    function debtValue(
        uint256 shares
    ) external returns (uint256 value);

    /// @notice Collects any earned rewards from staking, incentives, etc. Transfers to sender
    /// @dev Should be limited to LIQUIDATOR_MANAGER. Rewards must be collected before claimed
    /// @return amounts amount of rewards claimed for each token
    /// @return tokens tokens claimed
    function collectRewards() external returns (uint256[] memory amounts, address[] memory tokens);

    /// @notice Pull any non-tracked token to the specified destination
    /// @dev Should be limited to TOKEN_RECOVERY_MANAGER
    function recover(address[] calldata tokens, uint256[] calldata amounts, address[] calldata destinations) external;

    /// @notice Recovers any extra underlying both in DV and staked externally not tracked as debt.
    /// @dev Should be limited to TOKEN_SAVER_ROLE.
    /// @param destination The address to send excess underlyer to.
    function recoverUnderlying(
        address destination
    ) external;

    /// @notice Deposit underlying to receive destination vault shares
    /// @param amount amount of base lp asset to deposit
    function depositUnderlying(
        uint256 amount
    ) external returns (uint256 shares);

    /// @notice Withdraw underlying by burning destination vault shares
    /// @param shares amount of destination vault shares to burn
    /// @param to destination of the underlying asset
    /// @return amount underlyer amount 'to' received
    function withdrawUnderlying(uint256 shares, address to) external returns (uint256 amount);

    /// @notice Burn specified shares for underlyer swapped to base asset
    /// @param shares amount of vault shares to burn
    /// @param to destination of the base asset
    /// @return amount base asset amount 'to' received
    /// @return tokens the tokens burned to get the base asset
    /// @return tokenAmounts the amount of the tokens burned to get the base asset
    function withdrawBaseAsset(
        uint256 shares,
        address to
    ) external returns (uint256 amount, address[] memory tokens, uint256[] memory tokenAmounts);

    /// @notice Mark this vault as shutdown so that autoPools can react
    function shutdown(
        VaultShutdownStatus reason
    ) external;

    /// @notice True if the vault has been shutdown
    function isShutdown() external view returns (bool);

    /// @notice Returns the reason for shutdown (or `Active` if not shutdown)
    function shutdownStatus() external view returns (VaultShutdownStatus);

    /// @notice Stats contract for this vault
    function getStats() external view returns (IDexLSTStats);

    /// @notice get the marketplace rewards
    /// @return rewardTokens list of reward token addresses
    /// @return rewardRates list of reward rates
    function getMarketplaceRewards() external returns (uint256[] memory rewardTokens, uint256[] memory rewardRates);

    /// @notice Get the address of the underlying pool the vault points to
    /// @return poolAddress address of the underlying pool
    function getPool() external view returns (address poolAddress);

    /// @notice Gets the spot price of the underlying LP token
    /// @dev Price validated to be inside our tolerance against safe price. Will revert if outside.
    /// @return price Value of 1 unit of the underlying LP token in terms of the base asset
    function getValidatedSpotPrice() external returns (uint256 price);

    /// @notice Gets the safe price of the underlying LP token
    /// @dev Price validated to be inside our tolerance against spot price. Will revert if outside.
    /// @return price Value of 1 unit of the underlying LP token in terms of the base asset
    function getValidatedSafePrice() external returns (uint256 price);

    /// @notice Get the lowest price we can get for the LP token
    /// @dev This price can be attacked is not validate to be in any range
    /// @return price Value of 1 unit of the underlying LP token in terms of the base asset
    function getUnderlyerFloorPrice() external returns (uint256 price);

    /// @notice Get the highest price we can get for the LP token
    /// @dev This price can be attacked is not validate to be in any range
    /// @return price Value of 1 unit of the underlying LP token in terms of the base asset
    function getUnderlyerCeilingPrice() external returns (uint256 price);

    /// @notice Set or unset  a hash as a signed message
    /// @dev Should be limited to DESTINATION_VAULTS_UPDATER. The set hash is used to validate a signature.
    /// This signature can be potentially used to claim offchain rewards earned by Destination Vaults.
    /// @param hash bytes32 hash of a payload
    /// @param flag boolean flag to indicate a validity of hash
    function setMessage(bytes32 hash, bool flag) external;

    /// @notice Allows to change the incentive calculator of destination vault
    /// @dev Only works when vault is shutdown, also validates the calculator before updating
    /// @param incentiveCalculator address of the new incentive calculator
    function setIncentiveCalculator(
        address incentiveCalculator
    ) external;

    /// @notice Allows to change the extension contract
    /// @dev Should be limited to DESTINATION_VAULT_MANAGER
    /// @param extension contract address
    function setExtension(
        address extension
    ) external;

    /// @notice Calls the execute function of the extension contract
    /// @dev Should be limited to DESTINATION_VAULT_MANAGER
    /// @dev Special care should be taken to ensure that balances hasn't been manipulated
    /// @param data any data that the extension contract needs
    function executeExtension(
        bytes calldata data
    ) external;

    /// @notice Returns the max recoup credit given during the withdraw of an undervalued destination
    function recoupMaxCredit() external view returns (uint256);
}
