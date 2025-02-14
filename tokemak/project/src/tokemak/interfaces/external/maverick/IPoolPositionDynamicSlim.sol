// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Maverick boosted position.
interface IPoolPositionDynamicSlim is IERC20 {
    /// @notice Gets token reserves in boosted position.
    function getReserves() external returns (uint256 reserveA, uint256 reserveB);

    /// @notice Pool that boosted position is for.
    function pool() external returns (address maverickPool);

    /// @notice Returns an array of all binIds that boosted position is active for.
    function allBinIds() external returns (uint128[] memory);
}
