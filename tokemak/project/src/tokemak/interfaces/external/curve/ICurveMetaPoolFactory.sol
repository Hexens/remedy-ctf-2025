// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase
/**
 * @notice This interface is used for interacting with the older version of the Curve factory at address
 *      `0x0959158b6040D32d04c301A72CBFD6b39E21c9AE`.  This factory can only be used to deploy metapools.
 */
interface ICurveMetaPoolFactory {
    /// @notice Gets coin addresses for pool deployed by factory.
    function get_coins(
        address pool
    ) external view returns (address[2] memory);

    /// @notice Gets balances of coins for pool deployed by factory.
    function get_balances(
        address pool
    ) external view returns (uint256[2] memory);
}
