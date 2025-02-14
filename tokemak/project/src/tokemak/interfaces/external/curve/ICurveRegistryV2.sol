// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

interface ICurveRegistryV2 {
    /**
     * @notice Gets address of lp token for pool.
     * @param pool Address of pool to get lp token for.
     */
    function get_lp_token(
        address pool
    ) external view returns (address);

    /**
     * Gets number of coins in a Curve pool.
     * @param pool Address of pool to get number of coins for.
     */
    function get_n_coins(
        address pool
    ) external view returns (uint256);

    /**
     * @notice Gets array of addresses of coins in pool.
     * @dev Will have address(0) in unused array slots.
     * @param pool Address of pool to get coins for.
     */
    function get_coins(
        address pool
    ) external view returns (address[8] memory);

    /**
     * @notice Returns balances for requested pool.
     * @dev Unused array slots will contain 0 value.
     * @param pool Address of pool to get balances for.
     */
    function get_balances(
        address pool
    ) external view returns (uint256[8] memory);

    /**
     * @notice Returns address of pool associated with lp token.
     * @param pool Address of pool.
     */
    function get_pool_from_lp_token(
        address pool
    ) external view returns (address);
}
