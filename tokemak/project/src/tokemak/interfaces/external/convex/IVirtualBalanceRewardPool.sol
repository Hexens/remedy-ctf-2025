// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IVirtualBalanceRewardPool {
    /// @notice The address of the asset token
    function deposits() external view returns (address);

    /// @notice Get total rewards supply
    function totalSupply() external view returns (uint256);

    /// @notice The address of the reward token
    function rewardToken() external view returns (IERC20);

    /// @notice Get balance of an address
    function balanceOf(
        address _account
    ) external view returns (uint256);

    /// @notice timestamp when reward period ends
    function periodFinish() external view returns (uint256);

    /// @notice The rate of reward distribution per block.
    function rewardRate() external view returns (uint256);

    /// @notice The amount of rewards distributed per staked token stored.
    function rewardPerToken() external view returns (uint256);

    /// @notice The duration for locking the token rewards.
    function duration() external view returns (uint256);
}
