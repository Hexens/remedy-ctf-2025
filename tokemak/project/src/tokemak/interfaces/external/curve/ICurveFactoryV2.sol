// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase, var-name-mixedcase

/**
 * @notice Curve factory for V2 contracts.
 */
interface ICurveFactoryV2 {
    /// @notice Gets coin addresses for pool deployed by factory.
    function get_coins(
        address pool
    ) external view returns (address[2] memory);

    /// @notice Gets balances of coins for pool deployed by factory.
    function get_balances(
        address pool
    ) external view returns (uint256[2] memory);

    function deploy_pool(
        string memory name,
        string memory symbol,
        address[2] memory coins,
        uint256 a,
        uint256 gamma,
        uint256 mid_fee,
        uint256 out_fee,
        uint256 allowed_extra_profit,
        uint256 fee_gamma,
        uint256 adjustment_step,
        uint256 admin_fee,
        uint256 ma_half_time,
        uint256 initial_price
    ) external returns (address);
}
