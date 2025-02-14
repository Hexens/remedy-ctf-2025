// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Roles } from "src/tokemak/libs/Roles.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { IStrategy } from "src/tokemak/interfaces/strategy/IStrategy.sol";
import { IAutopoolStrategy } from "src/tokemak/interfaces/strategy/IAutopoolStrategy.sol";
import { IAutopool } from "src/tokemak/interfaces/vault/IAutopool.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { ViolationTracking } from "src/tokemak/strategy/ViolationTracking.sol";
import { NavTracking } from "src/tokemak/strategy/NavTracking.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";
import { AutopoolETHStrategyConfig } from "src/tokemak/strategy/AutopoolETHStrategyConfig.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { AutopoolDebt } from "src/tokemak/vault/libs/AutopoolDebt.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { StrategyUtils } from "src/tokemak/strategy/libs/StrategyUtils.sol";
import { SubSaturateMath } from "src/tokemak/strategy/libs/SubSaturateMath.sol";
import { SummaryStats } from "src/tokemak/strategy/libs/SummaryStats.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Incentives } from "src/tokemak/strategy/libs/Incentives.sol";

contract AutopoolETHStrategy is SystemComponent, Initializable, IAutopoolStrategy, SecurityBase {
    using ViolationTracking for ViolationTracking.State;
    using NavTracking for NavTracking.State;
    using SubSaturateMath for uint256;
    using SubSaturateMath for int256;
    using Math for uint256;

    /* ******************************** */
    /* Immutable Config                 */
    /* ******************************** */

    /// @notice the number of days to pause rebalancing due to NAV decay
    uint16 public immutable pauseRebalancePeriodInDays;

    /// @notice the number of seconds gap between consecutive rebalances
    uint256 public immutable rebalanceTimeGapInSeconds;

    /// @notice destinations trading a premium above maxPremium will be blocked from new capital deployments
    int256 public immutable maxPremium; // 100% = 1e18

    /// @notice destinations trading a discount above maxDiscount will be blocked from new capital deployments
    int256 public immutable maxDiscount; // 100% = 1e18

    /// @notice the allowed staleness of stats data before a revert occurs
    uint40 public immutable staleDataToleranceInSeconds;

    /// @notice the swap cost offset period to initialize the strategy with
    uint16 public immutable swapCostOffsetInitInDays;

    /// @notice the number of violations required to trigger a tightening of the swap cost offset period (1 to 10)
    uint16 public immutable swapCostOffsetTightenThresholdInViolations;

    /// @notice the number of days to decrease the swap offset period for each tightening step
    uint16 public immutable swapCostOffsetTightenStepInDays;

    /// @notice the number of days since a rebalance required to trigger a relaxing of the swap cost offset period
    uint16 public immutable swapCostOffsetRelaxThresholdInDays;

    /// @notice the number of days to increase the swap offset period for each relaxing step
    uint16 public immutable swapCostOffsetRelaxStepInDays;

    // slither-disable-start similar-names
    /// @notice the maximum the swap cost offset period can reach. This is the loosest the strategy will be
    uint16 public immutable swapCostOffsetMaxInDays;

    /// @notice the minimum the swap cost offset period can reach. This is the most conservative the strategy will be
    uint16 public immutable swapCostOffsetMinInDays;

    /// @notice the number of days for the first NAV decay comparison (e.g., 30 days)
    uint8 public immutable navLookback1InDays;

    /// @notice the number of days for the second NAV decay comparison (e.g., 60 days)
    uint8 public immutable navLookback2InDays;

    /// @notice the number of days for the third NAV decay comparison (e.g., 90 days)
    uint8 public immutable navLookback3InDays;
    // slither-disable-end similar-names

    /// @notice the maximum slippage that is allowed for a normal rebalance
    uint256 public immutable maxNormalOperationSlippage; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destination is trimmed due to constraint violations
    /// recommend setting this higher than maxNormalOperationSlippage
    uint256 public immutable maxTrimOperationSlippage; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destinationVault has been shutdown
    /// shutdown for a vault is abnormal and means there is an issue at that destination
    /// recommend setting this higher than maxNormalOperationSlippage
    uint256 public immutable maxEmergencyOperationSlippage; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when the AutopoolETH has been shutdown
    uint256 public immutable maxShutdownOperationSlippage; // 100% = 1e18

    /// @notice the maximum discount used for price return
    int256 public immutable maxAllowedDiscount; // 18 precision

    /// @notice model weight used for LSTs base yield, 1e6 is the highest
    uint256 public immutable weightBase;

    /// @notice model weight used for DEX fee yield, 1e6 is the highest
    uint256 public immutable weightFee;

    /// @notice model weight used for incentive yield
    uint256 public immutable weightIncentive;

    /// @notice model weight applied to an LST discount when exiting the position
    int256 public immutable weightPriceDiscountExit;

    /// @notice model weight applied to an LST discount when entering the position
    int256 public immutable weightPriceDiscountEnter;

    /// @notice model weight applied to an LST premium when entering or exiting the position
    int256 public immutable weightPricePremium;

    /// @notice initial value of the swap cost offset to use
    uint16 public immutable swapCostOffsetInit;

    uint256 public immutable defaultLstPriceGapTolerance;

    /// @notice Addresses of hook contracts
    address private immutable hook1;
    address private immutable hook2;
    address private immutable hook3;
    address private immutable hook4;
    address private immutable hook5;

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    /// @notice model weight applied to an LST premium when entering or exiting the position
    uint256 public lstPriceGapTolerance;

    /// @notice Dust position portions
    /// @dev Value is determined as 1/f then truncated to a integer value, where f is a fractional value < 1.0.
    /// For ex. f = 0.02 means a position < 0.02 will be treated as a dust position
    uint256 public dustPositionPortions;

    /// @notice Idle Threshold Low
    /// @dev Fractional value < 1.0 represented in 18 decimals
    /// For ex. a value = 4e16 means 4% of total assets in the vault
    uint256 public idleLowThreshold;

    /// @notice Idle Threshold High
    /// @dev Fractional value < 1.0 represented in 18 decimals
    /// For ex. a value = 7e16 means 7% of total assets in the vault
    /// Low & high idle thresholds trigger different behaviors. When idle is less than low threshold, idle level must be
    /// brought up to high threshold. Any amount > high threshold is free to be deployed to destinations. When idle lies
    /// between low & high threshold, it does not trigger new idle to be added.
    uint256 public idleHighThreshold;

    /// @notice The AutopoolETH that this strategy is associated with
    IAutopool public autoPool;

    /// @notice The timestamp for when rebalancing was last paused
    uint40 public lastPausedTimestamp;

    /// @notice The last timestamp that a destination was added to
    mapping(address => uint40) public lastAddTimestampByDestination;

    /// @notice The last timestamp a rebalance was completed
    uint40 public lastRebalanceTimestamp;

    /// @notice Rebalance violation tracking state
    ViolationTracking.State public violationTrackingState;

    /// @notice NAV tracking state
    NavTracking.State public navTrackingState;

    uint16 private _swapCostOffsetPeriod;

    /* ******************************** */
    /* Events                           */
    /* ******************************** */

    enum RebalanceToIdleReasonEnum {
        DestinationIsShutdown,
        AutopoolETHIsShutdown,
        TrimDustPosition,
        DestinationIsQueuedForRemoval,
        DestinationViolatedConstraint,
        ReplenishIdlePosition,
        UnknownReason
    }

    event RebalanceToIdleReason(RebalanceToIdleReasonEnum reason, uint256 maxSlippage, uint256 slippage);

    event DestTrimRebalanceDetails(
        uint256 assetIndex, uint256 numViolationsOne, uint256 numViolationsTwo, int256 discount
    );
    event DestViolationMaxTrimAmount(uint256 trimAmount);
    event RebalanceToIdle(
        SummaryStats.RebalanceValueStats valueStats, IStrategy.SummaryStats outSummary, IStrategy.RebalanceParams params
    );

    event RebalanceBetweenDestinations(
        SummaryStats.RebalanceValueStats valueStats,
        IStrategy.RebalanceParams params,
        IStrategy.SummaryStats outSummaryStats,
        IStrategy.SummaryStats inSummaryStats,
        uint256 swapOffsetPeriod,
        int256 predictedAnnualizedGain
    );

    event SuccessfulRebalanceBetweenDestinations(
        address destinationOut,
        uint40 lastRebalanceTimestamp,
        uint40 lastTimestampAddedToDestination,
        uint40 swapCostOffsetPeriod
    );

    event PauseStart(uint256 navPerShare, uint256 nav1, uint256 nav2, uint256 nav3);
    event PauseStop();

    event LstPriceGapSet(uint256 newPriceGap);
    event DustPositionPortionSet(uint256 newValue);
    event IdleThresholdsSet(uint256 newLowValue, uint256 newHighValue);

    /* ******************************** */
    /* Errors                           */
    /* ******************************** */
    error NotAutopoolETH();
    error StrategyPaused();
    error RebalanceTimeGapNotMet();
    error RebalanceDestinationsMatch();
    error RebalanceDestinationUnderlyerMismatch(address destination, address trueUnderlyer, address providedUnderlyer);

    error StaleData(string name);
    error SwapCostExceeded();
    error MaxSlippageExceeded();
    error MaxDiscountExceeded();
    error MaxPremiumExceeded();
    error OnlyRebalanceToIdleAvailable();
    error InvalidRebalanceToIdle();
    error CannotConvertUintToInt();
    error InsufficientAssets(address asset);
    error SystemRegistryMismatch();
    error UnregisteredDestination(address dest);
    error LSTPriceGapToleranceExceeded();
    error InconsistentIdleThresholds();
    error IdleHighThresholdViolated();

    modifier onlyAutopool() {
        if (msg.sender != address(autoPool)) revert NotAutopoolETH();
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry,
        AutopoolETHStrategyConfig.StrategyConfig memory conf
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        AutopoolETHStrategyConfig.validate(conf);

        rebalanceTimeGapInSeconds = conf.rebalanceTimeGapInSeconds;
        pauseRebalancePeriodInDays = conf.pauseRebalancePeriodInDays;
        maxPremium = conf.maxPremium;
        maxDiscount = conf.maxDiscount;
        staleDataToleranceInSeconds = conf.staleDataToleranceInSeconds;
        swapCostOffsetInitInDays = conf.swapCostOffset.initInDays;
        swapCostOffsetTightenThresholdInViolations = conf.swapCostOffset.tightenThresholdInViolations;
        swapCostOffsetTightenStepInDays = conf.swapCostOffset.tightenStepInDays;
        swapCostOffsetRelaxThresholdInDays = conf.swapCostOffset.relaxThresholdInDays;
        swapCostOffsetRelaxStepInDays = conf.swapCostOffset.relaxStepInDays;
        swapCostOffsetMaxInDays = conf.swapCostOffset.maxInDays;
        swapCostOffsetMinInDays = conf.swapCostOffset.minInDays;
        navLookback1InDays = conf.navLookback.lookback1InDays;
        navLookback2InDays = conf.navLookback.lookback2InDays;
        navLookback3InDays = conf.navLookback.lookback3InDays;
        maxNormalOperationSlippage = conf.slippage.maxNormalOperationSlippage;
        maxTrimOperationSlippage = conf.slippage.maxTrimOperationSlippage;
        maxEmergencyOperationSlippage = conf.slippage.maxEmergencyOperationSlippage;
        maxShutdownOperationSlippage = conf.slippage.maxShutdownOperationSlippage;
        maxAllowedDiscount = conf.maxAllowedDiscount;
        weightBase = conf.modelWeights.baseYield;
        weightFee = conf.modelWeights.feeYield;
        weightIncentive = conf.modelWeights.incentiveYield;
        weightPriceDiscountExit = conf.modelWeights.priceDiscountExit;
        weightPriceDiscountEnter = conf.modelWeights.priceDiscountEnter;
        weightPricePremium = conf.modelWeights.pricePremium;
        defaultLstPriceGapTolerance = conf.lstPriceGapTolerance;
        swapCostOffsetInit = conf.swapCostOffset.initInDays;
        hook1 = conf.hooks[0];
        hook2 = conf.hooks[1];
        hook3 = conf.hooks[2];
        hook4 = conf.hooks[3];
        hook5 = conf.hooks[4];

        _disableInitializers();
    }

    function initialize(
        address _autoPool
    ) external virtual initializer {
        _initialize(_autoPool);
    }

    function _initialize(
        address _autoPool
    ) internal virtual {
        Errors.verifyNotZero(_autoPool, "_autoPool");

        if (ISystemComponent(_autoPool).getSystemRegistry() != address(systemRegistry)) {
            revert SystemRegistryMismatch();
        }

        autoPool = IAutopool(_autoPool);

        lastRebalanceTimestamp = uint40(block.timestamp) - uint40(rebalanceTimeGapInSeconds);
        _swapCostOffsetPeriod = swapCostOffsetInit;
        lstPriceGapTolerance = defaultLstPriceGapTolerance;
        dustPositionPortions = 50;
        idleLowThreshold = 0;
        idleHighThreshold = 0;
    }

    /// @notice Sets the LST price gap tolerance to the provided value
    function setLstPriceGapTolerance(
        uint256 priceGapTolerance
    ) external hasRole(Roles.AUTO_POOL_MANAGER) {
        lstPriceGapTolerance = priceGapTolerance;

        emit LstPriceGapSet(priceGapTolerance);
    }

    /// @notice Sets the dust position portions to the provided value
    function setDustPositionPortions(
        uint256 newValue
    ) external hasRole(Roles.AUTO_POOL_MANAGER) {
        dustPositionPortions = newValue;

        emit DustPositionPortionSet(newValue);
    }

    /// @notice Sets the Idle low/high threshold
    function setIdleThresholds(uint256 newLowValue, uint256 newHighValue) external hasRole(Roles.AUTO_POOL_MANAGER) {
        idleLowThreshold = newLowValue;
        idleHighThreshold = newHighValue;

        // Check for consistency in values i.e. low threshold should be strictly < high threshold
        if (((idleLowThreshold > 0 && idleHighThreshold > 0)) && (idleLowThreshold >= idleHighThreshold)) {
            revert InconsistentIdleThresholds();
        }
        // Setting both thresholds to 0 allows no minimum requirement for idle
        if ((idleLowThreshold == 0 && idleHighThreshold != 0) || (idleLowThreshold != 0 && idleHighThreshold == 0)) {
            revert InconsistentIdleThresholds();
        }

        emit IdleThresholdsSet(newLowValue, newHighValue);
    }

    /// @inheritdoc IAutopoolStrategy
    function verifyRebalance(
        IStrategy.RebalanceParams memory params,
        IStrategy.SummaryStats memory outSummary
    ) external returns (bool success, string memory message) {
        SummaryStats.RebalanceValueStats memory valueStats =
            SummaryStats.getRebalanceValueStats(params, address(autoPool));

        // moves from a destination back to eth only happen under specific scenarios
        // if the move is valid, the constraints are different than if assets are moving to a normal destination
        if (params.destinationIn == address(autoPool)) {
            verifyRebalanceToIdle(params, valueStats.slippage);
            // slither-disable-next-line reentrancy-events
            emit RebalanceToIdle(valueStats, outSummary, params);
            // exit early b/c the remaining constraints only apply when moving to a normal destination
            return (true, "");
        }

        // rebalances back to idle are allowed even when a strategy is paused
        // all other rebalances should be blocked in a paused state
        ensureNotPaused();

        // Ensure enough time has passed between rebalances
        if ((uint40(block.timestamp) - lastRebalanceTimestamp) < rebalanceTimeGapInSeconds) {
            revert RebalanceTimeGapNotMet();
        }

        // ensure that we're not exceeding top-level max slippage
        if (valueStats.slippage > maxNormalOperationSlippage) {
            revert MaxSlippageExceeded();
        }

        // ensure that idle is not depleted below the high threshold if we are pulling from Idle assets
        // totalAssets will be reduced by swap cost amount.
        if (params.destinationOut == address(autoPool)) {
            uint256 totalAssets = autoPool.totalAssets().subSaturate(valueStats.swapCost);
            if (autoPool.getAssetBreakdown().totalIdle < valueStats.outEthValue) {
                revert IdleHighThresholdViolated();
            } else if (
                (autoPool.getAssetBreakdown().totalIdle - valueStats.outEthValue)
                    < ((totalAssets * idleHighThreshold) / 1e18)
            ) {
                revert IdleHighThresholdViolated();
            }
        }

        IStrategy.SummaryStats memory inSummary = getRebalanceInSummaryStats(params);

        // ensure that the destination that is being added to doesn't exceed top-level premium/discount constraints
        if (inSummary.maxDiscount > maxDiscount) revert MaxDiscountExceeded();
        if (-inSummary.maxPremium > maxPremium) revert MaxPremiumExceeded();

        uint256 swapOffsetPeriod = swapCostOffsetPeriodInDays();

        // if the swap is only moving lp tokens from one destination to another
        // make the swap offset period more conservative b/c the gas costs/complexity is lower
        // Discard the fractional part resulting from div by 2 to be conservative
        if (params.tokenIn == params.tokenOut) {
            swapOffsetPeriod = swapOffsetPeriod / 2;
        }
        // slither-disable-start divide-before-multiply
        // equation is `compositeReturn * ethValue` / 1e18, which is multiply before divide
        // compositeReturn and ethValue are both 1e18 precision
        int256 predictedAnnualizedGain = (
            inSummary.compositeReturn * StrategyUtils.convertUintToInt(valueStats.inEthValue)
        ).subSaturate(outSummary.compositeReturn * StrategyUtils.convertUintToInt(valueStats.outEthValue)) / 1e18;

        // slither-disable-end divide-before-multiply
        int256 predictedGainAtOffsetEnd =
            (predictedAnnualizedGain * StrategyUtils.convertUintToInt(swapOffsetPeriod) / 365);

        // if the predicted gain in Eth by the end of the swap offset period is less than
        // the swap cost then revert b/c the vault will not offset slippage in sufficient time
        // slither-disable-next-line timestamp
        if (predictedGainAtOffsetEnd <= StrategyUtils.convertUintToInt(valueStats.swapCost)) revert SwapCostExceeded();
        // slither-disable-next-line reentrancy-events
        emit RebalanceBetweenDestinations(
            valueStats, params, outSummary, inSummary, swapOffsetPeriod, predictedAnnualizedGain
        );

        return (true, "");
    }

    function expiredRewardTolerance() external pure returns (uint256) {
        return Incentives.EXPIRED_REWARD_TOLERANCE;
    }

    /// @inheritdoc IAutopoolStrategy
    function getDestinationSummaryStats(
        address destAddress,
        IAutopoolStrategy.RebalanceDirection direction,
        uint256 amount
    ) external returns (IStrategy.SummaryStats memory) {
        address token =
            destAddress == address(autoPool) ? autoPool.asset() : IDestinationVault(destAddress).underlying();
        uint256 outPrice = _getInOutTokenPriceInEth(token, destAddress);
        return SummaryStats.getDestinationSummaryStats(
            autoPool, systemRegistry.incentivePricing(), destAddress, outPrice, direction, amount
        );
    }

    function validateRebalanceParams(
        IStrategy.RebalanceParams memory params
    ) internal view {
        Errors.verifyNotZero(params.destinationIn, "destinationIn");
        Errors.verifyNotZero(params.destinationOut, "destinationOut");
        Errors.verifyNotZero(params.tokenIn, "tokenIn");
        Errors.verifyNotZero(params.tokenOut, "tokenOut");
        Errors.verifyNotZero(params.amountIn, "amountIn");
        Errors.verifyNotZero(params.amountOut, "amountOut");

        ensureDestinationRegistered(params.destinationIn);
        ensureDestinationRegistered(params.destinationOut);

        // when a vault is shutdown, rebalancing can only pull assets from destinations back to the vault
        if (autoPool.isShutdown() && params.destinationIn != address(autoPool)) revert OnlyRebalanceToIdleAvailable();

        if (params.destinationIn == params.destinationOut) revert RebalanceDestinationsMatch();

        address baseAsset = autoPool.asset();

        // if the in/out destination is the AutopoolETH then the in/out token must be the baseAsset
        // if the in/out is not the AutopoolETH then the in/out token must match the destinations underlying token
        if (params.destinationIn == address(autoPool)) {
            if (params.tokenIn != baseAsset) {
                revert RebalanceDestinationUnderlyerMismatch(params.destinationIn, params.tokenIn, baseAsset);
            }
        } else {
            IDestinationVault inDest = IDestinationVault(params.destinationIn);
            if (params.tokenIn != inDest.underlying()) {
                revert RebalanceDestinationUnderlyerMismatch(params.destinationIn, inDest.underlying(), params.tokenIn);
            }
        }

        if (params.destinationOut == address(autoPool)) {
            if (params.tokenOut != baseAsset) {
                revert RebalanceDestinationUnderlyerMismatch(params.destinationOut, params.tokenOut, baseAsset);
            }
            if (params.amountOut > autoPool.getAssetBreakdown().totalIdle) {
                revert InsufficientAssets(params.tokenOut);
            }
        } else {
            IDestinationVault outDest = IDestinationVault(params.destinationOut);
            if (params.tokenOut != outDest.underlying()) {
                revert RebalanceDestinationUnderlyerMismatch(
                    params.destinationOut, outDest.underlying(), params.tokenOut
                );
            }
            if (params.amountOut > outDest.balanceOf(address(autoPool))) {
                revert InsufficientAssets(params.tokenOut);
            }
        }
    }

    function ensureDestinationRegistered(
        address dest
    ) private view {
        if (dest == address(autoPool)) return;
        if (!(autoPool.isDestinationRegistered(dest) || autoPool.isDestinationQueuedForRemoval(dest))) {
            revert UnregisteredDestination(dest);
        }
    }

    function verifyRebalanceToIdle(IStrategy.RebalanceParams memory params, uint256 slippage) internal {
        IDestinationVault outDest = IDestinationVault(params.destinationOut);

        // multiple scenarios can be active at a given time. We want to use the highest
        // slippage among the active scenarios.
        uint256 maxSlippage = 0;
        RebalanceToIdleReasonEnum reason = RebalanceToIdleReasonEnum.UnknownReason;
        // Scenario 1: the destination has been shutdown -- done when a fast exit is required
        if (outDest.isShutdown()) {
            reason = RebalanceToIdleReasonEnum.DestinationIsShutdown;
            maxSlippage = maxEmergencyOperationSlippage;
        }

        // Scenario 2: the AutopoolETH has been shutdown
        if (autoPool.isShutdown() && maxShutdownOperationSlippage > maxSlippage) {
            reason = RebalanceToIdleReasonEnum.AutopoolETHIsShutdown;
            maxSlippage = maxShutdownOperationSlippage;
        }

        // Scenario 3: Replenishing Idle requires trimming destination
        if (verifyIdleUpOperation(params) && maxNormalOperationSlippage > maxSlippage) {
            reason = RebalanceToIdleReasonEnum.ReplenishIdlePosition;
            maxSlippage = maxNormalOperationSlippage;
        }

        // Scenario 4: position is a dust position and should be trimmed
        if (verifyCleanUpOperation(params) && maxNormalOperationSlippage > maxSlippage) {
            reason = RebalanceToIdleReasonEnum.TrimDustPosition;
            maxSlippage = maxNormalOperationSlippage;
        }

        // Scenario 5: the destination has been moved out of the Autopools active destinations
        if (autoPool.isDestinationQueuedForRemoval(params.destinationOut) && maxNormalOperationSlippage > maxSlippage) {
            reason = RebalanceToIdleReasonEnum.DestinationIsQueuedForRemoval;
            maxSlippage = maxNormalOperationSlippage;
        }

        // Scenario 6: the destination needs to be trimmed because it violated a constraint
        if (maxTrimOperationSlippage > maxSlippage) {
            reason = RebalanceToIdleReasonEnum.DestinationViolatedConstraint;
            uint256 trimAmount = getDestinationTrimAmount(outDest); // this is expensive, can it be refactored?
            if (trimAmount < 1e18 && verifyTrimOperation(params, trimAmount)) {
                maxSlippage = maxTrimOperationSlippage;
            }
            // slither-disable-next-line reentrancy-events
            emit DestViolationMaxTrimAmount(trimAmount);
        }
        // slither-disable-next-line reentrancy-events
        emit RebalanceToIdleReason(reason, maxSlippage, slippage);

        // if none of the scenarios are active then this rebalance is invalid
        if (maxSlippage == 0) revert InvalidRebalanceToIdle();

        if (slippage > maxSlippage) revert MaxSlippageExceeded();
    }

    function verifyCleanUpOperation(
        IStrategy.RebalanceParams memory params
    ) internal view returns (bool) {
        IDestinationVault outDest = IDestinationVault(params.destinationOut);

        AutopoolDebt.DestinationInfo memory destInfo = autoPool.getDestinationInfo(params.destinationOut);
        // revert if information is too old
        ensureNotStaleData("DestInfo", destInfo.lastReport);
        // shares of the destination currently held by the AutopoolETH
        uint256 currentShares = outDest.balanceOf(address(autoPool));
        // withdrawals reduce totalAssets, but do not update the destinationInfo
        // adjust the current debt based on the currently owned shares
        uint256 currentDebt =
            destInfo.ownedShares == 0 ? 0 : destInfo.cachedDebtValue * currentShares / destInfo.ownedShares;

        // If the current position is the minimum portion, trim to idle is allowed
        // slither-disable-next-line divide-before-multiply
        if ((currentDebt * 1e18) < ((autoPool.totalAssets() * 1e18) / dustPositionPortions)) {
            return true;
        }

        return false;
    }

    function verifyIdleUpOperation(
        IStrategy.RebalanceParams memory params
    ) internal view returns (bool) {
        AutopoolDebt.DestinationInfo memory destInfo = autoPool.getDestinationInfo(params.destinationOut);
        // revert if information is too old
        ensureNotStaleData("DestInfo", destInfo.lastReport);
        uint256 currentIdle = autoPool.getAssetBreakdown().totalIdle;
        uint256 newIdle = currentIdle + params.amountIn;
        uint256 totalAssets = autoPool.totalAssets();
        // If idle is below low threshold, then allow replinishing Idle. New idle after rebalance should be above high
        // threshold. While totalAssets after this rebalance will be lower by swap loss, the ratio idle / total assets
        // as used is conservative.
        // Idle thresholds (both low & high) use 18 decimals
        // slither-disable-next-line divide-before-multiply
        if ((currentIdle * 1e18) / totalAssets < idleLowThreshold) {
            // Allow small margin to exceed high threshold to avoid precision issues & pricing differences
            if ((newIdle * 1e18) / totalAssets < idleHighThreshold + 1e16) {
                return true;
            }
        }

        return false;
    }

    function verifyTrimOperation(IStrategy.RebalanceParams memory params, uint256 trimAmount) internal returns (bool) {
        // if the position can be trimmed to zero, then no checks are necessary
        if (trimAmount == 0) {
            return true;
        }

        IDestinationVault outDest = IDestinationVault(params.destinationOut);

        AutopoolDebt.DestinationInfo memory destInfo = autoPool.getDestinationInfo(params.destinationOut);
        // revert if information is too old
        ensureNotStaleData("DestInfo", destInfo.lastReport);

        // shares of the destination currently held by the AutopoolETH
        uint256 currentShares = outDest.balanceOf(address(autoPool));

        // withdrawals reduce totalAssets, but do not update the destinationInfo
        // adjust the current debt based on the currently owned shares
        uint256 currentDebt =
            destInfo.ownedShares == 0 ? 0 : destInfo.cachedDebtValue * currentShares / destInfo.ownedShares;

        // prior validation ensures that currentShares >= amountOut
        uint256 sharesAfterRebalance = currentShares - params.amountOut;

        // current value of the destination shares, not cached from debt reporting
        uint256 destValueAfterRebalance = outDest.debtValue(sharesAfterRebalance);

        // calculate the total value of the autoPool after the rebalance is made
        // note that only the out destination value is adjusted to current
        // amountIn is a minimum to receive, but it is OK if we receive more
        uint256 autoPoolAssetsAfterRebalance =
            (autoPool.totalAssets() + params.amountIn + destValueAfterRebalance - currentDebt);

        // trimming may occur over multiple rebalances, so we only want to ensure we aren't removing too much
        if (autoPoolAssetsAfterRebalance > 0) {
            return destValueAfterRebalance * 1e18 / autoPoolAssetsAfterRebalance >= trimAmount;
        } else {
            // Autopool assets after rebalance are 0
            return true;
        }
    }

    function getDestinationTrimAmount(
        IDestinationVault dest
    ) internal returns (uint256) {
        uint256 discountThresholdOne = 3e5; // 3% 1e7 precision, discount required to consider trimming
        uint256 discountDaysThreshold = 7; // number of last 10 days that it was >= discountThreshold
        uint256 discountThresholdTwo = 5e5; // 5% 1e7 precision, discount required to completely exit

        // this is always the out destination and guaranteed not to be the AutopoolETH idle asset
        IDexLSTStats.DexLSTStatsData memory stats = dest.getStats().current();

        ILSTStats.LSTStatsData[] memory lstStats = stats.lstStatsData;
        uint256 numLsts = lstStats.length;

        uint256 minTrim = 1e18; // 100% -- no trim required
        for (uint256 i = 0; i < numLsts; ++i) {
            ILSTStats.LSTStatsData memory targetLst = lstStats[i];
            (uint256 numViolationsOne, uint256 numViolationsTwo) =
                getDiscountAboveThreshold(targetLst.discountHistory, discountThresholdOne, discountThresholdTwo);

            // slither-disable-next-line reentrancy-events
            emit DestTrimRebalanceDetails(i, numViolationsOne, numViolationsTwo, targetLst.discount);

            if (targetLst.discount >= int256(discountThresholdTwo * 1e11) && numViolationsTwo >= discountDaysThreshold)
            {
                // this is the worst possible trim, so we can exit without checking other LSTs

                return 0;
            }

            // discountThreshold is 1e7 precision for the discount history, but here it is compared to a 1e18, so pad it
            if (targetLst.discount >= int256(discountThresholdOne * 1e11) && numViolationsOne >= discountDaysThreshold)
            {
                minTrim = minTrim.min(1e17); // 10%
            }
        }

        return minTrim;
    }

    function getDiscountAboveThreshold(
        uint24[10] memory discountHistory,
        uint256 threshold1,
        uint256 threshold2
    ) internal pure returns (uint256 count1, uint256 count2) {
        count1 = 0;
        count2 = 0;
        uint256 len = discountHistory.length;
        for (uint256 i = 0; i < len; ++i) {
            if (discountHistory[i] >= threshold1) {
                count1 += 1;
            }
            if (discountHistory[i] >= threshold2) {
                count2 += 1;
            }
        }
    }

    /// @inheritdoc IAutopoolStrategy
    function getRebalanceOutSummaryStats(
        IStrategy.RebalanceParams memory rebalanceParams
    ) external returns (IStrategy.SummaryStats memory outSummary) {
        validateRebalanceParams(rebalanceParams);
        // Verify spot & safe price for the individual tokens in the pool are not far apart.
        // Call to verify before remove/add liquidity to the dest in the rebalance txn
        // if the in dest is not the Autopool i.e. this is not a rebalance to idle txn, verify price tolerance
        if (rebalanceParams.destinationIn != address(autoPool)) {
            if (!SummaryStats.verifyLSTPriceGap(autoPool, rebalanceParams, lstPriceGapTolerance)) {
                revert LSTPriceGapToleranceExceeded();
            }
        }
        outSummary = _getRebalanceOutSummaryStats(rebalanceParams);
    }

    function _getRebalanceOutSummaryStats(
        IStrategy.RebalanceParams memory rebalanceParams
    ) internal virtual returns (IStrategy.SummaryStats memory outSummary) {
        // Use safe price
        uint256 outPrice = _getInOutTokenPriceInEth(rebalanceParams.tokenOut, rebalanceParams.destinationOut);
        outSummary = (
            SummaryStats.getDestinationSummaryStats(
                autoPool,
                systemRegistry.incentivePricing(),
                rebalanceParams.destinationOut,
                outPrice,
                RebalanceDirection.Out,
                rebalanceParams.amountOut
            )
        );
    }

    /// @dev Price the tokens from rebalance params with the appropriate method
    function _getInOutTokenPriceInEth(address token, address destination) private returns (uint256) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        if (destination == address(autoPool)) {
            // When the destination is the autoPool then the token is the underlying asset
            // which means its not an LP token so we use this pricing fn
            return pricer.getPriceInEth(token);
        } else {
            // Otherwise we know its a real destination and so we can get the price directly from there
            return IDestinationVault(destination).getValidatedSafePrice();
        }
    }

    // Summary stats for destination In
    function getRebalanceInSummaryStats(
        IStrategy.RebalanceParams memory rebalanceParams
    ) internal virtual returns (IStrategy.SummaryStats memory inSummary) {
        // Use safe price
        uint256 inPrice = _getInOutTokenPriceInEth(rebalanceParams.tokenIn, rebalanceParams.destinationIn);
        inSummary = (
            SummaryStats.getDestinationSummaryStats(
                autoPool,
                systemRegistry.incentivePricing(),
                rebalanceParams.destinationIn,
                inPrice,
                RebalanceDirection.In,
                rebalanceParams.amountIn
            )
        );
    }

    /// @inheritdoc IAutopoolStrategy
    function navUpdate(
        uint256 navPerShare
    ) external onlyAutopool {
        uint40 blockTime = uint40(block.timestamp);
        navTrackingState.insert(navPerShare, blockTime);

        clearExpiredPause();

        // check if the strategy needs to be paused due to NAV decay
        // the check only happens after there are enough data points
        // skip the check if the strategy is already paused
        // slither-disable-next-line timestamp
        if (navTrackingState.len > navLookback3InDays && !paused()) {
            uint256 nav1 = navTrackingState.getDaysAgo(navLookback1InDays);
            uint256 nav2 = navTrackingState.getDaysAgo(navLookback2InDays);
            uint256 nav3 = navTrackingState.getDaysAgo(navLookback3InDays);

            if (navPerShare < nav1 && navPerShare < nav2 && navPerShare < nav3) {
                lastPausedTimestamp = blockTime;
                emit PauseStart(navPerShare, nav1, nav2, nav3);
            }
        }
    }

    /// @inheritdoc IAutopoolStrategy
    function rebalanceSuccessfullyExecuted(
        IStrategy.RebalanceParams memory params
    ) external onlyAutopool {
        // clearExpirePause sets _swapCostOffsetPeriod, so skip when possible to avoid double write
        if (!clearExpiredPause()) _swapCostOffsetPeriod = swapCostOffsetPeriodInDays();

        address autoPoolAddress = address(autoPool);

        // update the destination that had assets added
        // moves into idle are not tracked for violations
        if (params.destinationIn != autoPoolAddress) {
            // Update to lastRebalanceTimestamp excludes rebalances to idle as those skip swapCostOffset logic
            lastRebalanceTimestamp = uint40(block.timestamp);
            lastAddTimestampByDestination[params.destinationIn] = lastRebalanceTimestamp;
        }

        // violations are only tracked when moving between non-idle assets
        if (params.destinationOut != autoPoolAddress && params.destinationIn != autoPoolAddress) {
            uint40 lastAddForRemoveDestination = lastAddTimestampByDestination[params.destinationOut];
            uint40 swapCostOffsetPeriod = uint40(swapCostOffsetPeriodInDays());
            if (
                // slither-disable-start timestamp
                lastRebalanceTimestamp - lastAddForRemoveDestination < swapCostOffsetPeriod * 1 days
            ) {
                // slither-disable-end timestamp

                violationTrackingState.insert(true);
            } else {
                violationTrackingState.insert(false);
            }
            emit SuccessfulRebalanceBetweenDestinations(
                params.destinationOut, lastRebalanceTimestamp, lastAddForRemoveDestination, swapCostOffsetPeriod
            );
        }

        // tighten if X of the last 10 rebalances were violations
        if (
            violationTrackingState.len == 10
                && violationTrackingState.violationCount >= swapCostOffsetTightenThresholdInViolations
        ) {
            tightenSwapCostOffset();
            violationTrackingState.reset();
        }
    }

    /// @inheritdoc IAutopoolStrategy
    function getHooks() public view virtual override returns (address[] memory hooks) {
        hooks = new address[](5);
        hooks[0] = hook1;
        hooks[1] = hook2;
        hooks[2] = hook3;
        hooks[3] = hook4;
        hooks[4] = hook5;
    }

    function swapCostOffsetPeriodInDays() public view returns (uint16) {
        // if the system is in an expired pause state then ensure that swap cost offset
        // is set to the most conservative value (shortest number of days)
        if (expiredPauseState()) {
            return swapCostOffsetMinInDays;
        }

        // truncation is desirable because we only want the number of times it has exceeded the threshold
        // slither-disable-next-line divide-before-multiply
        uint40 numRelaxPeriods = swapCostOffsetRelaxThresholdInDays == 0
            ? 0
            : (uint40(block.timestamp) - lastRebalanceTimestamp) / 1 days / uint40(swapCostOffsetRelaxThresholdInDays);
        uint40 relaxDays = numRelaxPeriods * uint40(swapCostOffsetRelaxStepInDays);
        uint40 newSwapCostOffset = uint40(_swapCostOffsetPeriod) + relaxDays;

        // slither-disable-next-line timestamp
        if (newSwapCostOffset > swapCostOffsetMaxInDays) {
            return swapCostOffsetMaxInDays;
        }

        return uint16(newSwapCostOffset);
    }

    function tightenSwapCostOffset() internal {
        uint16 currentSwapOffset = swapCostOffsetPeriodInDays();
        uint16 newSwapCostOffset = 0;

        if (currentSwapOffset > swapCostOffsetTightenStepInDays) {
            newSwapCostOffset = currentSwapOffset - swapCostOffsetTightenStepInDays;
        }

        // slither-disable-next-line timestamp
        if (newSwapCostOffset < swapCostOffsetMinInDays) {
            _swapCostOffsetPeriod = swapCostOffsetMinInDays;
        } else {
            _swapCostOffsetPeriod = newSwapCostOffset;
        }
    }

    function paused() public view returns (bool) {
        // slither-disable-next-line incorrect-equality,timestamp
        if (lastPausedTimestamp == 0) return false;
        uint40 pauseRebalanceInSeconds = uint40(pauseRebalancePeriodInDays) * 1 days;

        // slither-disable-next-line timestamp
        return uint40(block.timestamp) - lastPausedTimestamp <= pauseRebalanceInSeconds;
    }

    function ensureNotPaused() internal view {
        if (paused()) revert StrategyPaused();
    }

    function expiredPauseState() internal view returns (bool) {
        // slither-disable-next-line timestamp
        return lastPausedTimestamp > 0 && !paused();
    }

    function clearExpiredPause() internal returns (bool) {
        if (!expiredPauseState()) return false;

        lastPausedTimestamp = 0;
        emit PauseStop();
        _swapCostOffsetPeriod = swapCostOffsetMinInDays;
        return true;
    }

    function ensureNotStaleData(string memory name, uint256 dataTimestamp) internal view {
        // slither-disable-next-line timestamp
        if (block.timestamp - dataTimestamp > staleDataToleranceInSeconds) revert StaleData(name);
    }
}
