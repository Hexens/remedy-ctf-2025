// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";

library Stats {
    uint256 public constant SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant DEX_FEE_APR_SNAPSHOT_INTERVAL = 24 * 60 * 60; // daily
    uint256 public constant DEX_FEE_APR_FILTER_INIT_INTERVAL = 9 * 24 * 60 * 60; // 9 days
    uint256 public constant DEX_FEE_ALPHA = 1e17; // 0.1; must be less than 1e18

    uint256 public constant INCENTIVE_INFO_SNAPSHOT_INTERVAL = 24 * 60 * 60; // daily

    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice thrown if end timestamp is before start timestamp
    error IncorrectTimestamps();

    /// @notice thrown if a divisor is zero
    error ZeroDivisor();

    /// @notice thrown if expecting a negative change but get a positive change
    error NonNegativeChange();

    /// @dev When registering dependent calculators, use this value for tokens/pools/etc that should be ignored
    bytes32 public constant NOOP_APR_ID = keccak256(abi.encode("NOOP_APR_ID"));

    error CalculatorAssetMismatch(bytes32 aprId, address calculator, address coin);

    error DependentAprIdsMismatchTokens(uint256 numDependentAprIds, uint256 numCoins);

    /// @notice Generate an id for a stat calc representing a base ERC20
    /// @dev For rETH/stETH/cbETH etc. Do not use for pools, LP tokens, staking platforms.
    /// @param tokenAddress address of the token
    function generateRawTokenIdentifier(
        address tokenAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode("erc20", tokenAddress));
    }

    /// @notice Generate an aprId for a curve pool
    /// @param poolAddress address of the curve pool
    function generateCurvePoolIdentifier(
        address poolAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode("curve", poolAddress));
    }

    /// @notice Generate an aprId for a balancer pool
    /// @param poolAddress address of the balancer pool
    function generateBalancerPoolIdentifier(
        address poolAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode("balancer", poolAddress));
    }

    //slither-disable-start dead-code
    /// @notice Generate an aprId for a proxy lst calc
    /// @param tokenAddress address of token
    function generateProxyIdentifier(
        address tokenAddress
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode("proxy", tokenAddress));
    }
    //slither-disable-end dead-code

    function calculateAnnualizedChangeMinZero(
        uint256 startTimestamp,
        uint256 startValue,
        uint256 endTimestamp,
        uint256 endValue
    ) internal pure returns (uint256) {
        if (startValue == 0) revert ZeroDivisor();
        if (endTimestamp <= startTimestamp) revert IncorrectTimestamps();
        if (endValue <= startValue) return 0;

        uint256 unannualized = (endValue * 1e18) / startValue - 1e18;
        uint256 timeDiff = endTimestamp - startTimestamp;

        return unannualized * SECONDS_IN_YEAR / timeDiff;
    }

    function getFilteredValue(
        uint256 alpha,
        uint256 priorValue,
        uint256 currentValue
    ) internal pure returns (uint256) {
        if (alpha > 1e18 || alpha == 0) revert Errors.InvalidParam("alpha");
        return ((priorValue * (1e18 - alpha)) + (currentValue * alpha)) / 1e18;
    }

    /**
     * @dev Decays credits based on the elapsed time and reward rate.
     * Credits decay when the current time is past the reward period finish time
     * or when the reward rate is zero.
     *
     * @param currentCredits The current amount of credits.
     * @return The adjusted amount of credits after potential decay.
     */
    function decayCredits(uint8 currentCredits, uint256 hoursPassed) internal pure returns (uint8) {
        // slither-disable-start timestamp
        currentCredits = uint8((hoursPassed > currentCredits) ? 0 : currentCredits - hoursPassed);
        // slither-disable-end timestamp

        return currentCredits;
    }

    /**
     * @notice Checks if the difference between two values is more than 5%.
     * @param value1 The first value.
     * @param value2 The second value.
     * @return A boolean indicating if the difference between the two values is more than 5%.
     */
    function differsByMoreThanFivePercent(uint256 value1, uint256 value2) internal pure returns (bool) {
        if (value1 > value2) {
            return value1 > (value2 + (value2 / 20)); // value2 / 20 represents 5% of value2
        } else {
            return value2 > (value1 + (value1 / 20)); // value1 / 20 represents 5% of value1
        }
    }
}
