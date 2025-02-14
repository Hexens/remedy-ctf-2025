// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAerodromeGauge {
    /// @notice Deposit LP tokens into gauge for any user
    /// @param _amount .
    function deposit(
        uint256 _amount
    ) external;

    /// @notice Deposit LPs into gauge
    function deposit(uint256 _amount, address _recipient) external;

    /// @notice Withdraw LP tokens for user
    /// @param _amount .
    function withdraw(
        uint256 _amount
    ) external;

    /// @notice Address of the pool LP token which is deposited (staked) for rewards
    function stakingToken() external view returns (address);

    /// @notice Address of the token (AERO) rewarded to stakers
    function rewardToken() external view returns (address);

    /// @notice Retrieve rewards for an address.
    /// @dev Throws if not called by same address or voter.
    /// @param _account .
    function getReward(
        address _account
    ) external;

    /// @notice Get the amount of stakingToken deposited by an account
    function balanceOf(
        address
    ) external view returns (uint256);

    /// @notice Returns accrued balance to date from last claim / first deposit.
    function earned(
        address _account
    ) external view returns (uint256 _earned);

    /// @notice Returns if gauge is linked to a legitimate Protocol pool
    function isPool() external view returns (bool);

    /// @notice Current reward rate of rewardToken to distribute per second
    function rewardRate() external view returns (uint256);

    /// @notice Timestamp end of current rewards period
    function periodFinish() external view returns (uint256);

    /// @notice Most recent stored value of rewardPerToken
    function rewardPerToken() external view returns (uint256);

    /// @notice Get the total amount of stakingToken staked for rewards
    function totalSupply() external view returns (uint256);
}
