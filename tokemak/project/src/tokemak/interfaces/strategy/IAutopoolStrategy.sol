// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IStrategy } from "src/tokemak/interfaces/strategy/IStrategy.sol";

interface IAutopoolStrategy {
    enum RebalanceDirection {
        In,
        Out
    }

    /// @notice verify that a rebalance (swap between destinations) meets all the strategy constraints
    /// @dev Signature identical to IStrategy.verifyRebalance
    function verifyRebalance(
        IStrategy.RebalanceParams memory,
        IStrategy.SummaryStats memory
    ) external returns (bool, string memory message);

    /// @notice called by the Autopool when NAV is updated
    /// @dev can only be called by the strategy's registered Autopool
    /// @param navPerShare The navPerShare to record
    function navUpdate(
        uint256 navPerShare
    ) external;

    /// @notice called by the Autopool when a rebalance is completed
    /// @dev can only be called by the strategy's registered Autopool
    /// @param rebalanceParams The parameters for the rebalance that was executed
    function rebalanceSuccessfullyExecuted(
        IStrategy.RebalanceParams memory rebalanceParams
    ) external;

    /// @notice called by the Autopool during rebalance process
    /// @param rebalanceParams The parameters for the rebalance that was executed
    function getRebalanceOutSummaryStats(
        IStrategy.RebalanceParams memory rebalanceParams
    ) external returns (IStrategy.SummaryStats memory outSummary);

    /// @notice Returns stats for a given destination
    /// @dev Used to evaluate the current state of the destinations and decide best action
    /// @param destAddress Destination address. Can be a DestinationVault or the AutoPool
    /// @param direction Direction to evaluate the stats at
    /// @param amount Amount to evaluate the stats at
    function getDestinationSummaryStats(
        address destAddress,
        IAutopoolStrategy.RebalanceDirection direction,
        uint256 amount
    ) external returns (IStrategy.SummaryStats memory);

    /// @notice Returns all hooks registered on strategy
    /// @dev Will return zero addresses for unregistered hooks
    /// @return hooks Array of hook addresses
    function getHooks() external view returns (address[] memory hooks);

    /// @notice the number of days to pause rebalancing due to NAV decay
    function pauseRebalancePeriodInDays() external view returns (uint16);

    /// @notice the number of seconds gap between consecutive rebalances
    function rebalanceTimeGapInSeconds() external view returns (uint256);

    /// @notice destinations trading a premium above maxPremium will be blocked from new capital deployments
    function maxPremium() external view returns (int256); // 100% = 1e18

    /// @notice destinations trading a discount above maxDiscount will be blocked from new capital deployments
    function maxDiscount() external view returns (int256); // 100% = 1e18

    /// @notice the allowed staleness of stats data before a revert occurs
    function staleDataToleranceInSeconds() external view returns (uint40);

    /// @notice the swap cost offset period to initialize the strategy with
    function swapCostOffsetInitInDays() external view returns (uint16);

    /// @notice the number of violations required to trigger a tightening of the swap cost offset period (1 to 10)
    function swapCostOffsetTightenThresholdInViolations() external view returns (uint16);

    /// @notice the number of days to decrease the swap offset period for each tightening step
    function swapCostOffsetTightenStepInDays() external view returns (uint16);

    /// @notice the number of days since a rebalance required to trigger a relaxing of the swap cost offset period
    function swapCostOffsetRelaxThresholdInDays() external view returns (uint16);

    /// @notice the number of days to increase the swap offset period for each relaxing step
    function swapCostOffsetRelaxStepInDays() external view returns (uint16);

    // slither-disable-start similar-names
    /// @notice the maximum the swap cost offset period can reach. This is the loosest the strategy will be
    function swapCostOffsetMaxInDays() external view returns (uint16);

    /// @notice the minimum the swap cost offset period can reach. This is the most conservative the strategy will be
    function swapCostOffsetMinInDays() external view returns (uint16);

    /// @notice the number of days for the first NAV decay comparison (e.g., 30 days)
    function navLookback1InDays() external view returns (uint8);

    /// @notice the number of days for the second NAV decay comparison (e.g., 60 days)
    function navLookback2InDays() external view returns (uint8);

    /// @notice the number of days for the third NAV decay comparison (e.g., 90 days)
    function navLookback3InDays() external view returns (uint8);
    // slither-disable-end similar-names

    /// @notice the maximum slippage that is allowed for a normal rebalance
    function maxNormalOperationSlippage() external view returns (uint256); // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destination is trimmed due to constraint violations
    /// recommend setting this higher than maxNormalOperationSlippage
    function maxTrimOperationSlippage() external view returns (uint256); // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destinationVault has been shutdown
    /// shutdown for a vault is abnormal and means there is an issue at that destination
    /// recommend setting this higher than maxNormalOperationSlippage
    function maxEmergencyOperationSlippage() external view returns (uint256); // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when the Autopool has been shutdown
    function maxShutdownOperationSlippage() external view returns (uint256); // 100% = 1e18

    /// @notice the maximum discount used for price return
    function maxAllowedDiscount() external view returns (int256); // 18 precision

    /// @notice model weight used for LSTs base yield, 1e6 is the highest
    function weightBase() external view returns (uint256);

    /// @notice model weight used for DEX fee yield, 1e6 is the highest
    function weightFee() external view returns (uint256);

    /// @notice model weight used for incentive yield
    function weightIncentive() external view returns (uint256);

    /// @notice model weight applied to an LST discount when exiting the position
    function weightPriceDiscountExit() external view returns (int256);

    /// @notice model weight applied to an LST discount when entering the position
    function weightPriceDiscountEnter() external view returns (int256);

    /// @notice model weight applied to an LST premium when entering or exiting the position
    function weightPricePremium() external view returns (int256);

    /// @notice initial value of the swap cost offset to use
    function swapCostOffsetInit() external view returns (uint16);

    /// @notice initial lst price gap tolerance
    function defaultLstPriceGapTolerance() external view returns (uint256);
}
