// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IBaseRewarder } from "src/tokemak/interfaces/rewarders/IBaseRewarder.sol";
import { IExtraRewarder } from "src/tokemak/interfaces/rewarders/IExtraRewarder.sol";

interface IMainRewarder is IBaseRewarder {
    error ExtraRewardsNotAllowed();
    error MaxExtraRewardsReached();

    /// @notice Extra rewards can be added, but not removed, ref: https://github.com/Tokemak/v2-core/issues/659
    event ExtraRewardAdded(address reward);

    /**
     * @notice Adds an ExtraRewarder contract address to the extraRewards array.
     * @param reward The address of the ExtraRewarder contract.
     */
    function addExtraReward(
        address reward
    ) external;

    /**
     * @notice Withdraws the specified amount of tokens from the vault for the specified account, and transfers all
     * rewards for the account from this contract and any linked extra reward contracts.
     * @param account The address of the account to withdraw tokens and claim rewards for.
     * @param amount The amount of tokens to withdraw.
     * @param claim If true, claims all rewards for the account from this contract and any linked extra reward
     * contracts.
     */
    function withdraw(address account, uint256 amount, bool claim) external;

    /**
     * @notice Claims and transfers all rewards for the specified account from this contract and any linked extra reward
     * contracts.
     * @dev If claimExtras is true, also claims all rewards from linked extra reward contracts.
     * @param account The address of the account to claim rewards for.
     * @param recipient The address to send the rewards to.
     * @param claimExtras If true, claims rewards from linked extra reward contracts.
     */
    function getReward(address account, address recipient, bool claimExtras) external;

    /**
     * @notice Number of extra rewards currently registered
     */
    function extraRewardsLength() external view returns (uint256);

    /**
     * @notice Get the extra rewards array values
     */
    function extraRewards() external view returns (address[] memory);

    /**
     * @notice Get the rewarder at the specified index
     */
    function getExtraRewarder(
        uint256 index
    ) external view returns (IExtraRewarder);
}
