// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "src/tokemak/external/balancer/FixedPoint.sol";

// solhint-disable max-line-length
// slither-disable-start dead-code

/// @dev Functionality taken from BalV3 monorepo. Original here -
/// https://github.com/balancer/balancer-v3-monorepo/blob/73708b75898a62dac0535f38d1bf471ac0e538c6/pkg/solidity-utils/contracts/helpers/ScalingHelpers.sol

/**
 * @notice Helper functions to apply/undo token decimal and rate adjustments, rounding in the direction indicated.
 * @dev To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had
 * 18 decimals. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be
 * represented as 1e18. This allows us to not consider differences in token decimals in the internal Pool
 * math, simplifying it greatly.
 *
 * These helpers can also be used to scale amounts by other 18-decimal floating point values, such as rates.
 */
library ScalingHelpers {
    using FixedPoint for *;
    using ScalingHelpers for uint256;

    /**
     *
     *                             Single Value Functions
     *
     */

    /**
     * @notice Applies `scalingFactor` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling or not. The result
     * is rounded down.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final 18-decimal precision result, rounded down
     */
    function toScaled18RoundDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulDown(amount, scalingFactor);
    }

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded down
     */
    function toScaled18ApplyRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulDown(scalingFactor).mulDown(tokenRate);
    }

    /**
     * @notice Applies `scalingFactor` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling or not. The result
     * is rounded up.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final 18-decimal precision result, rounded up
     */
    function toScaled18RoundUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulUp(amount, scalingFactor);
    }

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded up
     */
    function toScaled18ApplyRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulUp(scalingFactor).mulUp(tokenRate);
    }

    /**
     * @notice Reverses the `scalingFactor` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling or not. The result
     * is rounded down.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final native decimal result, rounded down
     */
    function toRawRoundDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divDown(amount, scalingFactor);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded down
     */
    function toRawUndoRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last, and round scalingFactor * tokenRate up to divide by a larger number.
        return FixedPoint.divDown(amount, scalingFactor.mulUp(tokenRate));
    }

    /**
     * @notice Reverses the `scalingFactor` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling or not. The result
     * is rounded up.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final native decimal result, rounded up
     */
    function toRawRoundUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divUp(amount, scalingFactor);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded up
     */
    function toRawUndoRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last, and round scalingFactor * tokenRate down to divide by a smaller number.
        return FixedPoint.divUp(amount, scalingFactor.mulDown(tokenRate));
    }
}
// slither-disable-end dead-code
