// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

//                   ██
//                   ██
//                   ██
//                   ██
//                   ██
//      █████████████████████████████████████████
//                                 ██
//                                 ██
//                                 ██
//                                 ██
//                                 ██

import { Roles } from "src/tokemak/libs/Roles.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { AutopoolDebt } from "src/tokemak/vault/libs/AutopoolDebt.sol";
import { Pausable } from "src/tokemak/security/Pausable.sol";
import { VaultTypes } from "src/tokemak/vault/VaultTypes.sol";
import { NonReentrant } from "src/tokemak/utils/NonReentrant.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { AutopoolFees } from "src/tokemak/vault/libs/AutopoolFees.sol";
import { AutopoolToken } from "src/tokemak/vault/libs/AutopoolToken.sol";
import { Autopool4626 } from "src/tokemak/vault/libs/Autopool4626.sol";
import { IStrategy } from "src/tokemak/interfaces/strategy/IStrategy.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { WithdrawalQueue } from "src/tokemak/strategy/WithdrawalQueue.sol";
import { AutopoolDestinations } from "src/tokemak/vault/libs/AutopoolDestinations.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { IMainRewarder } from "src/tokemak/interfaces/rewarders/IMainRewarder.sol";
import { StructuredLinkedList } from "src/tokemak/strategy/StructuredLinkedList.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";

// solhint-disable max-states-count

contract AutopoolETH is ISystemComponent, Initializable, IAutopool, IStrategy, SecurityBase, Pausable, NonReentrant {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;
    using WithdrawalQueue for StructuredLinkedList.List;
    using AutopoolToken for AutopoolToken.TokenData;

    /// Be careful around the use of totalSupply and balanceOf. If you go directly to the _tokenData struct you may miss
    /// out on the profit share unlock logic or the checking the balance of the pool itself

    /// =====================================================
    /// Constant Vars
    /// =====================================================

    /// @notice 100% == 10000
    uint256 public constant FEE_DIVISOR = 10_000;

    /// @notice Amount of weth to be sent to vault on initialization.
    uint256 public constant WETH_INIT_DEPOSIT = 100_000;

    /// @notice Dead address for init share burn.
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    /// @notice Overarching baseAsset type
    bytes32 public immutable vaultType = VaultTypes.LST;

    // solhint-disable-next-line var-name-mixedcase
    uint256 public immutable ONE;

    /// @notice Instance of this system this vault is tied to
    /// @dev Exposed via `getSystemRegistry()`
    ISystemRegistry internal immutable _systemRegistry;

    /// @notice The asset that is deposited into the vault
    /// @dev Exposed via `asset()`
    IERC20Metadata internal immutable _baseAsset;

    /// @notice Decimals of the base asset. Used as the decimals for the vault itself
    /// @dev Exposed via `decimals()`
    uint8 internal immutable _baseAssetDecimals;

    /// =====================================================
    /// Internal Vars
    /// =====================================================

    /// @notice Balances, allowances, and supply for the pool
    /// @dev Want to keep this var in this position
    AutopoolToken.TokenData internal _tokenData;

    /// @notice Pool/token name
    string internal _name;

    /// @notice Pool/token symbol
    string internal _symbol;

    /// @notice Full list of possible destinations that could be deployed to
    /// @dev Exposed via `getDestinations()`
    EnumerableSet.AddressSet internal _destinations;

    /// @notice Destinations that are queued for removal
    /// @dev Exposed via `getRemovalQueue`
    EnumerableSet.AddressSet internal _removalQueue;

    /// @notice Lookup of destinationVaultAddress -> Info .. Debt reporting snapshot info
    /// @dev Exposed via `getDestinationInfo`
    mapping(address => AutopoolDebt.DestinationInfo) internal _destinationInfo;

    /// @notice Whether or not the vault has been shutdown
    /// @dev Exposed via `isShutdown()`
    bool internal _shutdown;

    /// @notice Reason for shutdown (or `Active` if not shutdown)
    /// @dev Exposed via `shutdownStatus()`
    VaultShutdownStatus internal _shutdownStatus;

    /// @notice Ordered list of destinations to withdraw from
    /// @dev Exposed via `getWithdrawalQueue()`
    StructuredLinkedList.List internal _withdrawalQueue;

    /// @notice Ordered list of destinations to debt report on. Ordered from oldest to newest
    /// @dev Exposed via `getDebtReportingQueue()`
    StructuredLinkedList.List internal _debtReportQueue;

    /// @notice State and settings related to gradual profit unlock
    /// @dev Exposed via `getProfitUnlockSettings()`
    IAutopool.ProfitUnlockSettings internal _profitUnlockSettings;

    /// @notice State and settings related to periodic and streaming fees
    /// @dev Exposed via `getFeeSettings()`
    IAutopool.AutopoolFeeSettings internal _feeSettings;

    /// @notice Asset tracking for idle and debt values
    /// @dev Exposed via `getAssetBreakdown()`
    IAutopool.AssetBreakdown internal _assetBreakdown;

    /// @notice Rewarders that have been replaced.
    /// @dev Exposed via `getPastRewarders()`
    EnumerableSet.AddressSet internal _pastRewarders;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Factory contract that created this vault
    address public factory;

    /// @notice Main rewarder for this contract
    IMainRewarder public rewarder;

    /// @notice The strategy logic for the Autopool
    IAutopoolStrategy public autoPoolStrategy;

    /// =====================================================
    /// Events
    /// =====================================================

    event SymbolAndDescSet(string symbol, string desc);

    /// =====================================================
    /// Errors
    /// =====================================================

    error WithdrawShareCalcInvalid(uint256 currentShares, uint256 cachedShares);
    error RewarderAlreadySet();
    error RebalanceDestinationsMatch(address destinationVault);
    error InvalidDestination(address destination);
    error NavChanged(uint256 oldNav, uint256 newNav);
    error NavOpsInProgress();
    error VaultShutdown();
    error NavDecreased(uint256 oldNav, uint256 newNav);
    error InvalidUser();

    /// =====================================================
    /// Modifiers
    /// =====================================================

    /// @notice Reverts if nav/share decreases during a deposit/mint/withdraw/redeem
    /// @dev Increases are allowed. Ignored when supply is 0
    modifier noNavPerShareDecrease(
        TotalAssetPurpose purpose
    ) {
        (uint256 oldNav, uint256 startingTotalSupply) = _snapStartNav(purpose);
        _;
        _ensureNoNavPerShareDecrease(oldNav, startingTotalSupply, purpose);
    }

    /// @notice Reverts if any nav/share changing operations are in progress across the system
    /// @dev Any rebalance or debtReporting on any pool
    modifier ensureNoNavOps() {
        _checkNoNavOps();
        _;
    }

    /// @notice Globally track operations that change nav/share in a vault
    /// @dev Doesn't revert, only meant to track so that `ensureNoNavOps()` can revert when appropriate
    modifier trackNavOps() {
        _systemRegistry.systemSecurity().enterNavOperation();
        _;
        // slither-disable-next-line reentrancy-no-eth
        _systemRegistry.systemSecurity().exitNavOperation();
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry systemRegistry,
        address _vaultAsset
    ) SecurityBase(address(systemRegistry.accessController())) Pausable(systemRegistry) {
        Errors.verifyNotZero(address(systemRegistry), "systemRegistry");
        _systemRegistry = systemRegistry;

        uint8 dec = IERC20Metadata(_vaultAsset).decimals();

        ONE = 10 ** dec;

        _baseAssetDecimals = dec;
        _baseAsset = IERC20Metadata(_vaultAsset);
        _symbol = string(abi.encodePacked("autoPool", IERC20Metadata(_vaultAsset).symbol(), "Template"));
        _name = string(abi.encodePacked(_symbol, " Token"));

        _disableInitializers();
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    function initialize(
        address strategy,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes memory
    ) external virtual initializer {
        Errors.verifyNotEmpty(symbolSuffix, "symbolSuffix");
        Errors.verifyNotEmpty(descPrefix, "descPrefix");
        Errors.verifyNotZero(strategy, "autoPoolStrategyAddress");

        factory = msg.sender;

        _symbol = symbolSuffix;
        _name = descPrefix;

        AutopoolFees.initializeFeeSettings(_feeSettings);

        autoPoolStrategy = IAutopoolStrategy(strategy);

        // slither-disable-start reentrancy-no-eth

        // Send 100_000 shares to dead address to prevent nav / share inflation attack that can happen
        // with very small shares and totalAssets amount.
        uint256 sharesMinted = deposit(WETH_INIT_DEPOSIT, DEAD_ADDRESS);

        // First mint, must be 1:1
        if (sharesMinted != WETH_INIT_DEPOSIT) revert ValueSharesMismatch(WETH_INIT_DEPOSIT, sharesMinted);

        // slither-disable-end reentrancy-no-eth

        AutopoolFees.setProfitUnlockPeriod(_profitUnlockSettings, _tokenData, 86_400);
    }

    /// @notice Mints Vault shares to receiver by depositing exactly amount of underlying tokens
    /// @dev No nav/share changing operations, debt reportings or rebalances,
    /// can be happening throughout the entire system
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        noNavPerShareDecrease(TotalAssetPurpose.Deposit)
        ensureNoNavOps
        returns (uint256 shares)
    {
        Errors.verifyNotZero(assets, "assets");

        uint256 ta = _totalAssetsTimeChecked(TotalAssetPurpose.Deposit);

        // Handles the vault being paused, returns 0
        uint256 maxDepositAmount = _maxDeposit(receiver, ta);
        if (assets > maxDepositAmount) {
            revert ERC4626DepositExceedsMax(assets, maxDepositAmount);
        }

        shares = convertToShares(assets, ta, totalSupply(), Math.Rounding.Down);

        Errors.verifyNotZero(shares, "shares");

        _transferAndMint(assets, shares, receiver);
    }

    /// @notice Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        noNavPerShareDecrease(TotalAssetPurpose.Deposit)
        ensureNoNavOps
        returns (uint256 assets)
    {
        // Handles the vault being paused, returns 0
        if (shares > maxMint(receiver)) {
            revert ERC4626MintExceedsMax(shares, maxMint(receiver));
        }

        uint256 ta = _totalAssetsTimeChecked(TotalAssetPurpose.Deposit);
        assets = convertToAssets(shares, ta, totalSupply(), Math.Rounding.Up);

        _transferAndMint(assets, shares, receiver);
    }

    /// @notice Burns shares from owner and sends exactly assets of underlying tokens to receiver.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        noNavPerShareDecrease(TotalAssetPurpose.Withdraw)
        ensureNoNavOps
        returns (uint256 shares)
    {
        Errors.verifyNotZero(assets, "assets");

        //slither-disable-next-line unused-return
        (uint256 actualAssets, uint256 actualShares,) = AutopoolDebt.withdraw(
            assets,
            _totalAssetsTimeChecked(TotalAssetPurpose.Withdraw),
            _assetBreakdown,
            _withdrawalQueue,
            _destinationInfo
        );

        shares = actualShares;

        _completeWithdrawal(actualAssets, shares, owner, receiver);
    }

    /// @notice Burns exactly shares from owner and sends assets of underlying tokens to receiver.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        noNavPerShareDecrease(TotalAssetPurpose.Withdraw)
        ensureNoNavOps
        returns (uint256 assets)
    {
        uint256 ta = _totalAssetsTimeChecked(TotalAssetPurpose.Withdraw);

        uint256 maxShares = _maxRedeem(owner, ta);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 possibleAssets = convertToAssets(shares, ta, totalSupply(), Math.Rounding.Down);
        Errors.verifyNotZero(possibleAssets, "possibleAssets");

        //slither-disable-next-line unused-return
        (uint256 actualAssets, uint256 actualShares,) =
            AutopoolDebt.redeem(possibleAssets, ta, _assetBreakdown, _withdrawalQueue, _destinationInfo);

        assets = actualAssets;

        assert(actualShares <= shares);

        _completeWithdrawal(assets, shares, owner, receiver);
    }

    /// @notice Enable or disable the high water mark on the rebalance fee
    /// @dev Will revert if set to the same value
    function setRebalanceFeeHighWaterMarkEnabled(
        bool enabled
    ) external hasRole(Roles.AUTO_POOL_FEE_UPDATER) {
        AutopoolFees.setRebalanceFeeHighWaterMarkEnabled(_feeSettings, enabled);
    }

    /// @notice Set the fee that will be taken when profit is realized
    /// @dev Resets the high water to current value
    /// @param fee Percent. 100% == 10000
    function setStreamingFeeBps(
        uint256 fee
    ) external nonReentrant hasRole(Roles.AUTO_POOL_FEE_UPDATER) {
        AutopoolFees.setStreamingFeeBps(_feeSettings, fee, oldestDebtReporting(), _debtReportQueue.size);
    }

    /// @notice Set the periodic fee taken.
    /// @dev Depending on time until next fee take, may update periodicFeeBps directly or queue fee.
    /// @param fee Fee to update periodic fee to.
    function setPeriodicFeeBps(
        uint256 fee
    ) external hasRole(Roles.AUTO_POOL_PERIODIC_FEE_UPDATER) {
        AutopoolFees.setPeriodicFeeBps(_feeSettings, fee, oldestDebtReporting(), _debtReportQueue.size);
    }

    /// @notice Set the address that will receive fees
    /// @param newFeeSink Address that will receive fees
    function setFeeSink(
        address newFeeSink
    ) external hasRole(Roles.AUTO_POOL_FEE_UPDATER) {
        AutopoolFees.setFeeSink(_feeSettings, newFeeSink);
    }

    /// @notice Sets the address that will receive periodic fees.
    /// @dev Zero address allowable.  Disables fees.
    /// @param newPeriodicFeeSink New periodic fee address.
    function setPeriodicFeeSink(
        address newPeriodicFeeSink
    ) external hasRole(Roles.AUTO_POOL_PERIODIC_FEE_UPDATER) {
        AutopoolFees.setPeriodicFeeSink(_feeSettings, newPeriodicFeeSink);
    }

    function setProfitUnlockPeriod(
        uint48 newUnlockPeriodSeconds
    ) external hasRole(Roles.AUTO_POOL_MANAGER) {
        AutopoolFees.setProfitUnlockPeriod(_profitUnlockSettings, _tokenData, newUnlockPeriodSeconds);
    }

    /// @notice Set the rewarder contract used by the vault.
    /// @param _rewarder Address of new rewarder.
    function setRewarder(
        address _rewarder
    ) external {
        // Factory needs to be able to call for vault creation.
        if (msg.sender != factory && !_hasRole(Roles.AUTO_POOL_REWARD_MANAGER, msg.sender)) {
            revert Errors.AccessDenied();
        }

        Errors.verifyNotZero(_rewarder, "rewarder");

        address toBeReplaced = address(rewarder);
        // Check that the new rewarder has not been a rewarder before, and that the current rewarder and
        //      new rewarder addresses are not the same.
        if (_pastRewarders.contains(_rewarder) || toBeReplaced == _rewarder) {
            revert Errors.ItemExists();
        }

        if (toBeReplaced != address(0)) {
            // slither-disable-next-line unused-return
            _pastRewarders.add(toBeReplaced);
        }

        rewarder = IMainRewarder(_rewarder);
        emit RewarderSet(_rewarder, toBeReplaced);
    }

    /// @inheritdoc IAutopool
    function getPastRewarders() external view returns (address[] memory) {
        return _pastRewarders.values();
    }

    /// @inheritdoc IAutopool
    function isPastRewarder(
        address _pastRewarder
    ) external view returns (bool) {
        return _pastRewarders.contains(_pastRewarder);
    }

    /// @notice Allow the updating of symbol/desc for the vault (only AFTER shutdown)
    function setSymbolAndDescAfterShutdown(
        string memory newSymbol,
        string memory newName
    ) external hasRole(Roles.AUTO_POOL_MANAGER) {
        Errors.verifyNotEmpty(newSymbol, "newSymbol");
        Errors.verifyNotEmpty(newName, "newName");

        // make sure the vault is no longer active
        if (_shutdownStatus == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(_shutdownStatus);
        }

        emit SymbolAndDescSet(newSymbol, newName);

        _symbol = newSymbol;
        _name = newName;
    }

    /// @inheritdoc IAutopool
    function isShutdown() external view returns (bool) {
        return _shutdown;
    }

    /// @inheritdoc IAutopool
    function shutdownStatus() external view returns (VaultShutdownStatus) {
        return _shutdownStatus;
    }

    /// @notice Returns state and settings related to gradual profit unlock
    function getProfitUnlockSettings() external view returns (IAutopool.ProfitUnlockSettings memory) {
        return _profitUnlockSettings;
    }

    /// @notice Returns state and settings related to periodic and streaming fees
    function getFeeSettings() external view returns (IAutopool.AutopoolFeeSettings memory) {
        return _feeSettings;
    }

    /// @notice Returns the name of the token
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the decimals of the token, same as the underlying asset
    function decimals() public view virtual override returns (uint8) {
        return _baseAssetDecimals;
    }

    /// @notice Returns the address of the underlying token used for the Vault for accounting, depositing, and
    /// withdrawing.
    function asset() public view virtual override returns (address) {
        return address(_baseAsset);
    }

    /// @notice Returns the total amount of the underlying asset that is “managed” by Vault.
    /// @dev Utilizes the "Global" purpose internally
    function totalAssets() public view override returns (uint256) {
        return Autopool4626.totalAssets(_assetBreakdown, TotalAssetPurpose.Global);
    }

    /// @notice Returns the total amount of the underlying asset that is “managed” by the Vault with respect to its
    /// usage
    /// @dev Value changes based on purpose. Global is an avg. Deposit is valued higher. Withdraw is valued lower.
    /// @param purpose The calculation the total assets will be used in
    function totalAssets(
        TotalAssetPurpose purpose
    ) public view returns (uint256) {
        return Autopool4626.totalAssets(_assetBreakdown, purpose);
    }

    function getAssetBreakdown() public view override returns (IAutopool.AssetBreakdown memory) {
        return _assetBreakdown;
    }

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided,
    /// in an ideal scenario where all the conditions are met
    function convertToShares(
        uint256 assets
    ) public view virtual returns (uint256 shares) {
        shares = convertToShares(assets, totalAssets(TotalAssetPurpose.Global), totalSupply(), Math.Rounding.Down);
    }

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided,
    /// in an ideal scenario where all the conditions are met
    function convertToShares(
        uint256 assets,
        uint256 totalAssetsForPurpose,
        uint256 supply,
        Math.Rounding rounding
    ) public view virtual returns (uint256 shares) {
        // slither-disable-next-line incorrect-equality
        shares = (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssetsForPurpose, rounding);
    }

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an
    /// ideal
    /// scenario where all the conditions are met.
    function convertToAssets(
        uint256 shares
    ) external view virtual returns (uint256 assets) {
        assets = convertToAssets(shares, totalAssets(TotalAssetPurpose.Global), totalSupply(), Math.Rounding.Down);
    }

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an
    /// ideal
    /// scenario where all the conditions are met.
    function convertToAssets(
        uint256 shares,
        uint256 totalAssetsForPurpose,
        uint256 supply,
        Math.Rounding rounding
    ) public view virtual returns (uint256 assets) {
        // slither-disable-next-line incorrect-equality
        assets = (supply == 0) ? shares : shares.mulDiv(totalAssetsForPurpose, supply, rounding);
    }

    /// @notice Returns the amount of unlocked profit shares that will be burned
    function unlockedShares() external view returns (uint256 shares) {
        shares = AutopoolFees.unlockedShares(_profitUnlockSettings, _tokenData);
    }

    /// @notice Returns the amount of tokens in existence.
    /// @dev Subtracts any unlocked profit shares that will be burned
    function totalSupply() public view virtual override(IERC20) returns (uint256 shares) {
        shares = Autopool4626.totalSupply(_tokenData, _profitUnlockSettings);
    }

    /// @notice Returns the amount of tokens owned by account.
    /// @dev Subtracts any unlocked profit shares that will be burned when account is the Vault itself
    function balanceOf(
        address account
    ) public view override(IERC20) returns (uint256) {
        return Autopool4626.balanceOf(_tokenData, _profitUnlockSettings, account);
    }

    /// @notice Returns the amount of tokens owned by wallet.
    /// @dev Does not subtract any unlocked profit shares that should be burned when wallet is the Vault itself
    function balanceOfActual(
        address account
    ) public view returns (uint256) {
        return _tokenData.balances[account];
    }

    /// @notice Returns the remaining number of tokens that `spender` will be allowed to spend on
    /// behalf of `owner` through {transferFrom}. This is zero by default
    /// @dev This value changes when `approve` or `transferFrom` are called
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _tokenData.allowances[owner][spender];
    }

    /// @notice Sets a `value` amount of tokens as the allowance of `spender` over the caller's tokens.
    function approve(address spender, uint256 value) public virtual returns (bool) {
        return _tokenData.approve(spender, value);
    }

    /// @notice Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism.
    /// `value` is then deducted from the caller's allowance.
    function transferFrom(address from, address to, uint256 value) public virtual whenNotPaused returns (bool) {
        return _tokenData.transferFrom(from, to, value);
    }

    /// @notice Moves a `value` amount of tokens from the caller's account to `to`
    function transfer(address to, uint256 value) public virtual whenNotPaused returns (bool) {
        return _tokenData.transfer(to, value);
    }

    /// @notice Returns the next unused nonce for an address.
    function nonces(
        address owner
    ) public view virtual returns (uint256) {
        return _tokenData.nonces[owner];
    }

    function getSystemRegistry() external view override returns (address) {
        return address(_systemRegistry);
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                AutopoolToken.TYPE_HASH,
                keccak256(bytes("Tokemak")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        _tokenData.permit(owner, spender, value, deadline, v, r, s);
    }

    /// @notice Returns the maximum amount of the underlying asset that can be
    /// deposited into the Vault for the receiver, through a deposit call
    function maxDeposit(
        address wallet
    ) public virtual override returns (uint256 maxAssets) {
        maxAssets = _maxDeposit(wallet, _totalAssetsTimeChecked(TotalAssetPurpose.Deposit));
    }

    /// @dev Local gas-saving function to pass pre-calculated total assets time checked value
    function _maxDeposit(address wallet, uint256 aptTotalAssets) private returns (uint256) {
        return convertToAssets(maxMint(wallet), aptTotalAssets, totalSupply(), Math.Rounding.Up);
    }

    /// @notice Simulate the effects of the deposit at the current block, given current on-chain conditions.
    function previewDeposit(
        uint256 assets
    ) public virtual returns (uint256 shares) {
        shares = convertToShares(
            assets, _totalAssetsTimeChecked(TotalAssetPurpose.Deposit), totalSupply(), Math.Rounding.Down
        );
    }

    /// @notice Returns the maximum amount of the Vault shares that
    /// can be minted for the receiver, through a mint call.
    function maxMint(
        address wallet
    ) public virtual override returns (uint256 maxShares) {
        maxShares = Autopool4626.maxMint(
            _tokenData, _profitUnlockSettings, _debtReportQueue, _destinationInfo, wallet, paused(), _shutdown
        );
    }

    /// @notice Returns the maximum amount of the underlying asset that can
    /// be withdrawn from the owner balance in the Vault, through a withdraw call
    function maxWithdraw(
        address owner
    ) public virtual returns (uint256 maxAssets) {
        uint256 ownerShareBalance = balanceOf(owner);
        uint256 taChecked = _totalAssetsTimeChecked(TotalAssetPurpose.Withdraw);

        if (paused() || ownerShareBalance == 0 || taChecked == 0) {
            return 0;
        }

        uint256 convertedAssets = convertToAssets(ownerShareBalance, taChecked, totalSupply(), Math.Rounding.Down);

        // slither-disable-next-line unused-return
        (maxAssets,) = AutopoolDebt.preview(
            true,
            convertedAssets,
            taChecked,
            abi.encodeCall(this.previewWithdraw, (convertedAssets)),
            _assetBreakdown,
            _withdrawalQueue,
            _destinationInfo
        );
    }

    /// @notice Returns the maximum amount of Vault shares that can be redeemed
    /// from the owner balance in the Vault, through a redeem call
    function maxRedeem(
        address owner
    ) public virtual returns (uint256 maxShares) {
        maxShares = _maxRedeem(owner, _totalAssetsTimeChecked(TotalAssetPurpose.Withdraw));
    }

    /// @dev Local gas-saving function to pass pre-calculated total assets time checked value
    function _maxRedeem(address owner, uint256 ta) private returns (uint256 maxShares) {
        // If total assets are zero then we are considered uncollateralized and all redeem's will fail
        if (ta > 0) {
            maxShares = paused() ? 0 : balanceOf(owner);
        }
    }

    function _totalAssetsTimeChecked(
        TotalAssetPurpose purpose
    ) private returns (uint256) {
        return AutopoolDebt.totalAssetsTimeChecked(_debtReportQueue, _destinationInfo, purpose);
    }

    /// @notice Simulate the effects of a mint at the current block, given current on-chain conditions
    function previewMint(
        uint256 shares
    ) public virtual returns (uint256 assets) {
        uint256 ta = _totalAssetsTimeChecked(TotalAssetPurpose.Deposit);
        assets = convertToAssets(shares, ta, totalSupply(), Math.Rounding.Up);
        Errors.verifyNotZero(assets, "assets");
    }

    /// @notice Simulate the effects of their withdrawal at the current block, given current on-chain conditions.
    function previewWithdraw(
        uint256 assets
    ) public virtual returns (uint256 shares) {
        // slither-disable-next-line unused-return
        (, shares) = AutopoolDebt.preview(
            true,
            assets,
            _totalAssetsTimeChecked(TotalAssetPurpose.Withdraw),
            abi.encodeCall(this.previewWithdraw, (assets)),
            _assetBreakdown,
            _withdrawalQueue,
            _destinationInfo
        );
    }

    /// @notice Simulate the effects of their redemption at the current block, given current on-chain conditions.
    function previewRedeem(
        uint256 shares
    ) public virtual override returns (uint256 assets) {
        // These values are not needed until the recursive call, gas savings.
        uint256 applicableTotalAssets = 0;
        uint256 convertedAssets = 0;
        if (msg.sender == address(this)) {
            applicableTotalAssets = _totalAssetsTimeChecked(TotalAssetPurpose.Withdraw);
            convertedAssets = convertToAssets(shares, applicableTotalAssets, totalSupply(), Math.Rounding.Down);
        }

        // slither-disable-next-line unused-return
        (assets,) = AutopoolDebt.preview(
            false,
            convertedAssets,
            applicableTotalAssets,
            abi.encodeCall(this.previewRedeem, (shares)),
            _assetBreakdown,
            _withdrawalQueue,
            _destinationInfo
        );
    }

    function _completeWithdrawal(uint256 assets, uint256 shares, address owner, address receiver) internal virtual {
        AutopoolDebt.completeWithdrawal(assets, shares, owner, receiver, _baseAsset, _assetBreakdown, _tokenData);
    }

    /// @notice Transfer out non-tracked tokens
    function recover(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address[] calldata destinations
    ) external virtual override hasRole(Roles.TOKEN_RECOVERY_MANAGER) {
        Autopool4626.recover(tokens, amounts, destinations);
    }

    /// @inheritdoc IAutopool
    function shutdown(
        VaultShutdownStatus reason
    ) external hasRole(Roles.AUTO_POOL_MANAGER) {
        if (reason == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(reason);
        }

        _shutdown = true;
        _shutdownStatus = reason;

        emit Shutdown(reason);
    }

    function _transferAndMint(uint256 assets, uint256 shares, address receiver) internal virtual {
        Autopool4626.transferAndMint(
            _baseAsset, _assetBreakdown, _tokenData, _profitUnlockSettings, assets, shares, receiver
        );
    }

    function updateDebtReporting(
        uint256 numToProcess
    ) external nonReentrant hasRole(Roles.AUTO_POOL_REPORTING_EXECUTOR) trackNavOps {
        // Persist our change in idle and debt
        uint256 startingIdle = _assetBreakdown.totalIdle;
        uint256 startingDebt = _assetBreakdown.totalDebt;

        // slither-disable-next-line reentrancy-no-eth
        AutopoolDebt.IdleDebtUpdates memory result =
            AutopoolDebt._updateDebtReporting(_debtReportQueue, _destinationInfo, numToProcess);

        uint256 newIdle = startingIdle + result.totalIdleIncrease;
        uint256 newDebt = startingDebt + result.totalDebtIncrease - result.totalDebtDecrease;

        _assetBreakdown.totalIdle = newIdle;
        _assetBreakdown.totalDebt = newDebt;
        _assetBreakdown.totalDebtMin =
            _assetBreakdown.totalDebtMin + result.totalMinDebtIncrease - result.totalMinDebtDecrease;
        _assetBreakdown.totalDebtMax =
            _assetBreakdown.totalDebtMax + result.totalMaxDebtIncrease - result.totalMaxDebtDecrease;

        uint256 newTotalSupply = _feeAndProfitHandling(newIdle + newDebt, startingIdle + startingDebt, true);

        _updateStrategyNav(newIdle + newDebt, newTotalSupply);

        emit Nav(newIdle, newDebt, newTotalSupply);
    }

    function _feeAndProfitHandling(
        uint256 newTotalAssets,
        uint256 startingTotalAssets,
        bool collectPeriodicFees
    ) internal returns (uint256 newTotalSupply) {
        // Collect any fees and lock any profit if appropriate
        AutopoolFees.burnUnlockedShares(_profitUnlockSettings, _tokenData);

        uint256 startingTotalSupply = totalSupply();

        newTotalSupply = _collectFees(newTotalAssets, startingTotalSupply, collectPeriodicFees);

        newTotalSupply = AutopoolFees.calculateProfitLocking(
            _profitUnlockSettings,
            _tokenData,
            newTotalSupply - startingTotalSupply, // new feeShares
            newTotalAssets,
            startingTotalAssets,
            newTotalSupply,
            balanceOfActual(address(this))
        );
    }

    function _collectFees(
        uint256 currentTotalAssets,
        uint256 currentTotalSupply,
        bool collectPeriodicFees
    ) internal virtual returns (uint256) {
        return AutopoolFees.collectFees(
            currentTotalAssets, currentTotalSupply, _feeSettings, _tokenData, collectPeriodicFees
        );
    }

    function getDestinations() public view override(IAutopool, IStrategy) returns (address[] memory) {
        return _destinations.values();
    }

    function getWithdrawalQueue() public view returns (address[] memory) {
        return _withdrawalQueue.getList();
    }

    function getDebtReportingQueue() public view returns (address[] memory) {
        return _debtReportQueue.getList();
    }

    /// @inheritdoc IAutopool
    function isDestinationRegistered(
        address destination
    ) external view returns (bool) {
        return _destinations.contains(destination);
    }

    function addDestinations(
        address[] calldata destinations
    ) public hasRole(Roles.AUTO_POOL_DESTINATION_UPDATER) {
        AutopoolDestinations.addDestinations(_removalQueue, _destinations, destinations, _systemRegistry);
    }

    function removeDestinations(
        address[] calldata destinations
    ) public hasRole(Roles.AUTO_POOL_DESTINATION_UPDATER) {
        AutopoolDestinations.removeDestinations(_removalQueue, _destinations, destinations);
    }

    function getRemovalQueue() public view override returns (address[] memory) {
        return _removalQueue.values();
    }

    /// @inheritdoc IAutopool
    function getDestinationInfo(
        address destVault
    ) external view returns (AutopoolDebt.DestinationInfo memory) {
        return _destinationInfo[destVault];
    }

    /// @inheritdoc IStrategy
    function flashRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams memory rebalanceParams,
        bytes calldata data
    ) public nonReentrant whenNotPaused hasRole(Roles.SOLVER) trackNavOps {
        AutopoolDebt.IdleDebtUpdates memory result = _processRebalance(receiver, rebalanceParams, data);

        uint256 idle = _assetBreakdown.totalIdle;
        uint256 debt = _assetBreakdown.totalDebt;
        uint256 startTotalAssets = idle + debt;

        idle = idle + result.totalIdleIncrease - result.totalIdleDecrease;
        debt = debt + result.totalDebtIncrease - result.totalDebtDecrease;

        _assetBreakdown.totalIdle = idle;
        _assetBreakdown.totalDebt = debt;
        _assetBreakdown.totalDebtMin =
            _assetBreakdown.totalDebtMin + result.totalMinDebtIncrease - result.totalMinDebtDecrease;
        _assetBreakdown.totalDebtMax =
            _assetBreakdown.totalDebtMax + result.totalMaxDebtIncrease - result.totalMaxDebtDecrease;

        uint256 newTotalSupply = _feeAndProfitHandling(idle + debt, startTotalAssets, false);

        // Ensure the destinations are in the queues they should be
        AutopoolDestinations._manageQueuesForDestination(
            rebalanceParams.destinationOut, false, _withdrawalQueue, _debtReportQueue, _removalQueue
        );
        AutopoolDestinations._manageQueuesForDestination(
            rebalanceParams.destinationIn, true, _withdrawalQueue, _debtReportQueue, _removalQueue
        );

        // Signal to the strategy that everything went well
        // and it can gather its final state/stats
        autoPoolStrategy.rebalanceSuccessfullyExecuted(rebalanceParams);

        _updateStrategyNav(idle + debt, newTotalSupply);

        emit Nav(idle, debt, newTotalSupply);
    }

    function _updateStrategyNav(uint256 assets, uint256 supply) internal virtual {
        autoPoolStrategy.navUpdate(assets * ONE / supply);
    }

    function _processRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams memory rebalanceParams,
        bytes calldata data
    ) internal virtual returns (AutopoolDebt.IdleDebtUpdates memory result) {
        // make sure there's something to do
        if (rebalanceParams.amountIn == 0 && rebalanceParams.amountOut == 0) {
            revert Errors.InvalidParams();
        }

        if (rebalanceParams.destinationIn == rebalanceParams.destinationOut) {
            revert RebalanceDestinationsMatch(rebalanceParams.destinationOut);
        }

        // Get out destination summary stats
        IStrategy.SummaryStats memory outSummary = autoPoolStrategy.getRebalanceOutSummaryStats(rebalanceParams);
        result = AutopoolDebt.flashRebalance(
            _destinationInfo[rebalanceParams.destinationOut],
            _destinationInfo[rebalanceParams.destinationIn],
            receiver,
            rebalanceParams,
            outSummary,
            autoPoolStrategy,
            AutopoolDebt.FlashRebalanceParams({
                totalIdle: _assetBreakdown.totalIdle,
                totalDebt: _assetBreakdown.totalDebt,
                baseAsset: _baseAsset,
                shutdown: _shutdown
            }),
            data
        );
    }

    /// @inheritdoc IAutopool
    function isDestinationQueuedForRemoval(
        address dest
    ) external view returns (bool) {
        return _removalQueue.contains(dest);
    }

    function oldestDebtReporting() public view returns (uint256) {
        address destVault = _debtReportQueue.peekHead();
        return _destinationInfo[destVault].lastReport;
    }

    function _checkNoNavOps() internal view {
        if (_systemRegistry.systemSecurity().navOpsInProgress() > 0) {
            revert NavOpsInProgress();
        }
    }

    function _snapStartNav(
        TotalAssetPurpose purpose
    ) private view returns (uint256 oldNav, uint256 startingTotalSupply) {
        startingTotalSupply = totalSupply();
        // slither-disable-next-line incorrect-equality
        if (startingTotalSupply == 0) {
            return (0, 0);
        }
        oldNav = (totalAssets(purpose) * FEE_DIVISOR) / startingTotalSupply;
    }

    /// @notice Vault nav/share shouldn't decrease on withdraw/redeem within rounding tolerance
    /// @dev No check when no shares
    function _ensureNoNavPerShareDecrease(
        uint256 oldNav,
        uint256 startingTotalSupply,
        TotalAssetPurpose purpose
    ) internal view virtual {
        uint256 ts = totalSupply();
        // slither-disable-next-line incorrect-equality
        if (ts == 0 || startingTotalSupply == 0) {
            return;
        }
        uint256 newNav = (totalAssets(purpose) * FEE_DIVISOR) / ts;
        if (newNav < oldNav) {
            revert NavDecreased(oldNav, newNav);
        }
    }
}
