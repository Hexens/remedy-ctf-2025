// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

/**
 * @notice Interface used for newer version of Curve factory at address `0xB9fC157394Af804a3578134A6585C0dc9cc990d4`.
 *      This factory used to deploy both stableswap and meta pools.
 */
interface ICurveMetaStableFactory {
    /// @notice Gets coin addresses for pool deployed by factory.
    function get_coins(
        address pool
    ) external view returns (address[4] memory);

    /// @notice Gets balances of coins for pool deployed by factory.
    function get_balances(
        address pool
    ) external view returns (uint256[4] memory);

    /// @notice Returns number of coins in pool.
    function get_n_coins(
        address pool
    ) external view returns (uint256);
}
