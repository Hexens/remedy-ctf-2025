// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable var-name-mixedcase,func-name-mixedcase

/// @notice Interface for next generation Curve pool oracle functionality.
interface ICurveStableSwapNG {
    /// @notice Returns current price in pool.
    function price_oracle() external view returns (uint256);

    function add_liquidity(uint256[] memory amounts, uint256 min_mint_amount) external payable returns (uint256);

    function remove_liquidity(uint256 amount, uint256[] memory min_amounts) external returns (uint256[] memory);
}
