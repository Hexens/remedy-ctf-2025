// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase, var-name-mixedcase
// slither-disable-start naming-convention
interface ICurveMetaRegistry {
    /// @notice Get the coins within a pool
    /// @dev For metapools, these are the wrapped coin addresses
    /// @param _pool Pool address
    /// @return List of coin addresses
    function get_coins(
        address _pool
    ) external view returns (address[8] memory);

    /// @notice Get the coins within a pool
    /// @dev For metapools, these are the wrapped coin addresses
    /// @param _pool Pool address
    /// @param _handler_id id of registry handler
    /// @return List of coin addresses
    function get_coins(address _pool, uint256 _handler_id) external view returns (address[8] memory);

    /// @notice Get the number of coins in a pool
    /// @dev For metapools, it is tokens + wrapping/lending token (no underlying)
    /// @param _pool Pool address
    /// @return Number of coins
    function get_n_coins(
        address _pool
    ) external view returns (uint256);

    /// @notice Get the number of coins in a pool
    /// @dev For metapools, it is tokens + wrapping/lending token (no underlying)
    /// @param _pool Pool address
    /// @param _handler_id Id of the registry to check
    /// @return Number of coins
    function get_n_coins(address _pool, uint256 _handler_id) external view returns (uint256);

    /// @notice Get the address of the LP token of a pool
    /// @param _pool Pool address
    /// @return Address of the LP token
    function get_lp_token(
        address _pool
    ) external view returns (address);

    /// @notice Get the address of the LP token of a pool
    /// @param _pool Pool address
    /// @param _handler_id id of registry handler
    /// @return Address of the LP token
    function get_lp_token(address _pool, uint256 _handler_id) external view returns (address);

    /// @notice Get the balances of the tokens in the pool
    /// @dev For metapools, these are the wrapped coin addresses
    /// @param _pool Pool address
    /// @return List of balances
    function get_balances(
        address _pool
    ) external view returns (uint256[8] memory);
}
// slither-disable-end naming-convention
