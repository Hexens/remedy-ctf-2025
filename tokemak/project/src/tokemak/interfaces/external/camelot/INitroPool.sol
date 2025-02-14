// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC721Enumerable } from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface INitroPool is IERC721Enumerable {
    /// @notice Returns the address of the rewards token 1
    function rewardsToken1() external view returns (address);

    /// @notice Returns the address of the rewards token 2
    function rewardsToken2() external view returns (address);

    /// @notice Harvest pending NitroPool rewards
    function harvest() external;
}
