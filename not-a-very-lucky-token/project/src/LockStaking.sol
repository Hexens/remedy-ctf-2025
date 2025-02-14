// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LockStaking is ReentrancyGuard {

    IERC20 public stakingToken;
    uint256 public rewardRate; // Reward per token per second (scaled by 1e18)
    uint256 public constant LOCK_TIME = 77 days;

    struct Stake {
        uint256 amount; // Amount of tokens staked
        uint256 unlockTime; // Timestamp when tokens can be withdrawn
        uint256 rewardDebt; // Accumulated rewards pending withdrawal
        uint256 lastUpdatedTime; // Last timestamp when rewards were calculated
    }

    mapping(address => Stake) public stakes;

    /**
     * @dev Constructor sets the staking token and the reward rate.
     * @param _stakingToken Address of the ERC20 token to be staked and rewarded.
     * @param _rewardRate Reward rate per token per second (scaled by 1e18).
     */
    constructor(address _stakingToken, uint256 _rewardRate) {
        stakingToken = IERC20(_stakingToken);
        rewardRate = _rewardRate;
    }

    /**
     * @dev Allows users to deposit tokens and start staking.
     * @param _amount Amount of tokens to stake.
     */
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Cannot stake zero tokens");

        Stake storage userStake = stakes[msg.sender];
        require(
            userStake.amount == 0,
            "Withdraw existing stake before depositing again"
        );

        // Transfer staking tokens to the contract
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Token transfer failed"
        );

        // Initialize user stake
        userStake.amount = _amount;
        userStake.unlockTime = block.timestamp + LOCK_TIME;
        userStake.lastUpdatedTime = block.timestamp;
        userStake.rewardDebt = 0;
    }

    /**
     * @dev Allows users to withdraw their staked tokens after the lock period.
     */
    function withdraw() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(
            block.timestamp >= userStake.unlockTime,
            "Tokens are still locked"
        );
        require(userStake.amount > 0, "No tokens to withdraw");

        // Update rewards before withdrawing
        _updateReward(msg.sender);

        uint256 amount = userStake.amount;

        // Reset user's stake
        userStake.amount = 0;
        userStake.unlockTime = 0;
        userStake.lastUpdatedTime = 0;
        userStake.rewardDebt = 0;

        // Transfer staked tokens back to the user
        require(
            stakingToken.transfer(msg.sender, amount),
            "Token transfer failed"
        );
    }

    /**
     * @dev Allows users to claim their pending rewards.
     */
    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);

        Stake storage userStake = stakes[msg.sender];
        uint256 pendingRewards = userStake.rewardDebt;
        require(pendingRewards > 0, "No rewards to claim");
        require(block.timestamp >= userStake.unlockTime + LOCK_TIME / 2, "Reward claiming is only possible if half of the LOCK_TIME has passed");

        // Reset pending rewards
        userStake.rewardDebt = 0;

        // Transfer rewards to the user
        require(
            stakingToken.transfer(msg.sender, pendingRewards),
            "Reward transfer failed"
        );
    }

    /**
     * @dev View function to check pending rewards for a user.
     * @param _user Address of the user.
     * @return Amount of pending rewards.
     */
    function pendingReward(address _user) external view returns (uint256) {
        Stake storage userStake = stakes[_user];
        uint256 accumulatedReward = userStake.rewardDebt;

        if (userStake.amount > 0) {
            uint256 lastTime = userStake.lastUpdatedTime;
            uint256 currentTime = block.timestamp > userStake.unlockTime
                ? userStake.unlockTime
                : block.timestamp;
            if (currentTime > lastTime) {
                uint256 timeElapsed = currentTime - lastTime;
                uint256 reward = (userStake.amount * rewardRate * timeElapsed) /
                    1e18;
                accumulatedReward += reward;
            }
        }
        return accumulatedReward;
    }

    /**
     * @dev Internal function to update rewards for a user.
     * @param _user Address of the user.
     */
    function _updateReward(address _user) internal {
        Stake storage userStake = stakes[_user];
        if (userStake.amount > 0) {
            uint256 lastTime = userStake.lastUpdatedTime;
            uint256 currentTime = block.timestamp > userStake.unlockTime
                ? userStake.unlockTime
                : block.timestamp;
            if (currentTime > lastTime) {
                uint256 timeElapsed = currentTime - lastTime;
                uint256 reward = (userStake.amount * rewardRate * timeElapsed) / 1e2;
                userStake.rewardDebt += reward;
                userStake.lastUpdatedTime = currentTime;
            }
        }
    }
}
