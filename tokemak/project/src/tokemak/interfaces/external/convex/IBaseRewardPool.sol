// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IBaseRewardPool {
    /// @notice The address of the staking token
    function stakingToken() external view returns (address);

    /// @notice The address of the reward token
    function rewardToken() external view returns (IERC20);

    /// @notice The length of the extra rewards array
    function extraRewardsLength() external view returns (uint256);

    /// @notice The pool PID
    function pid() external view returns (uint256);

    /// @notice The address of the extra rewards token at a given index
    function extraRewards(
        uint256 i
    ) external view returns (address);

    /// @notice Called by a staker to get their allocated rewards
    function getReward() external returns (bool);

    /// @notice Gives a staker their rewards, with the option of claiming extra rewards
    function getReward(address _account, bool _claimExtras) external returns (bool);

    /// @notice Get total rewards supply
    function totalSupply() external view returns (uint256);

    /// @notice Get balance of an address
    function balanceOf(
        address _account
    ) external view returns (uint256);

    /// @notice Withdraw directly to curve LP token
    function withdrawAndUnwrap(uint256 _amount, bool _claim) external returns (bool);

    /// @notice timestamp when reward period ends
    function periodFinish() external view returns (uint256);

    /// @notice The rate of reward distribution per block.
    function rewardRate() external view returns (uint256);

    /// @notice The amount of rewards distributed per staked token stored.
    function rewardPerToken() external view returns (uint256);

    /// @notice The duration for locking the token rewards.
    function duration() external view returns (uint256);
}
