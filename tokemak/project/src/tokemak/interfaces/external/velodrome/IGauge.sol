// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IGauge is IERC20 {
    function deposit(uint256 amount, uint256 tokenId) external;
    function withdraw(
        uint256 amount
    ) external;
    function withdrawToken(uint256 amount, uint256 tokenId) external;
    function stake() external view returns (address);
    function rewards(
        uint256 index
    ) external view returns (address);
    function rewardsListLength() external view returns (uint256);
    function getReward(address account, address[] memory tokens) external;
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
