// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

interface ICurveRegistry {
    /**
     * @notice Gets lp token address for Curve pool.
     * @param pool Address of pool to get lp token for.
     */
    function get_lp_token(
        address pool
    ) external view returns (address);

    /**
     * @notice Gets number of coins in pool.
     * @dev First value is coins in metaPool, second is including underlying pool.
     * @dev Each array value will be the same when pool is not meta or lending pool.
     * @param pool Address of pool to get coins for.
     */
    function get_n_coins(
        address pool
    ) external view returns (uint256[2] memory);

    /**
     * @notice Gets array of all coins in a pool.
     * @dev Will return address(0) for array slots that are not filled.
     * @param pool Address of pool to get coins for.
     */
    function get_coins(
        address pool
    ) external view returns (address[8] memory);

    /**
     * @notice Returns balances for pool tokens.
     * @dev Will returns zero for unused array slots.
     * @param pool Address of pool to get balances for.
     */
    function get_balances(
        address pool
    ) external view returns (uint256[8] memory);

    /**
     * @notice Gets pool address given lp token address.
     * @param lpToken Address of lp token being used to get pool address.
     */
    function get_pool_from_lp_token(
        address lpToken
    ) external view returns (address);
}
