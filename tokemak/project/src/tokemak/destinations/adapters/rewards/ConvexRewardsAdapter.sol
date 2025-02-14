// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { RewardAdapter } from "src/tokemak/destinations/adapters/rewards/RewardAdapter.sol";
import { IBaseRewardPool } from "src/tokemak/interfaces/external/convex/IBaseRewardPool.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IConvexStashToken } from "src/tokemak/interfaces/external/convex/IConvexStashToken.sol";

//slither-disable-start missing-inheritance,low-level-calls
library ConvexRewards {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Claim rewards for Convex staked LP tokens
    /// @dev tokens can be returned in any order. uint256(0)/address(0) can be returned
    /// @param gauge the reward contract in Convex
    /// @param defaultToken the reward token always provided. CVX for Convex
    /// @param sendTo the destination of the rewarded tokens
    /// @param trackedTokens tokens that should not be sent off to the 'sendTo'
    /// @return amounts the amount of each token that was claimed (includes balance already held by caller)
    /// @return tokens the tokens that were claimed
    function claimRewards(
        address gauge,
        address defaultToken,
        address sendTo,
        EnumerableSet.AddressSet storage trackedTokens
    ) public returns (uint256[] memory amounts, address[] memory tokens) {
        return _claimRewards(gauge, defaultToken, sendTo, trackedTokens);
    }

    /// @notice Claim rewards for Convex staked LP tokens
    /// @dev tokens can be returned in any order. uint256(0)/address(0) can be returned
    /// @param gauge the reward contract in Convex
    /// @param defaultToken the reward token always provided. CVX for Convex
    /// @param trackedTokens tokens that should not be sent off to the 'sendTo'
    /// @return amounts the amount of each token that was claimed (includes balance already held by caller)
    /// @return tokens the tokens that were claimed
    function claimRewards(
        address gauge,
        address defaultToken,
        EnumerableSet.AddressSet storage trackedTokens
    ) public returns (uint256[] memory amounts, address[] memory tokens) {
        return _claimRewards(gauge, defaultToken, address(this), trackedTokens);
    }

    /// @notice Claim rewards for Convex staked LP tokens
    /// @dev tokens can be returned in any order. uint256(0)/address(0) can be returned
    /// @param gauge the reward contract in Convex
    /// @param defaultToken the reward token always provided. CVX for Convex
    /// @param sendTo the destination of the rewarded tokens
    /// @param trackedTokens tokens that should not be sent off to the 'sendTo'
    /// @return amounts the amount of each token that was claimed (includes balance already held by caller)
    /// @return tokens the tokens that were claimed
    function _claimRewards(
        address gauge,
        address defaultToken,
        address sendTo,
        EnumerableSet.AddressSet storage trackedTokens
    ) internal returns (uint256[] memory amounts, address[] memory tokens) {
        Errors.verifyNotZero(gauge, "gauge");
        Errors.verifyNotZero(sendTo, "sendTo");

        address account = address(this);

        IBaseRewardPool rewardPool = IBaseRewardPool(gauge);
        uint256 extraRewardsLength = rewardPool.extraRewardsLength();

        // Convex mints their own token as part of the claim, thats the "defaultToken"
        // token in this case.
        uint256 totalLength = extraRewardsLength + (defaultToken != address(0) ? 2 : 1);

        uint256[] memory amountsClaimed = new uint256[](totalLength);
        address[] memory rewardTokens = new address[](totalLength);

        // add pool rewards tokens and extra rewards tokens to rewardTokens array
        IERC20 rewardToken = rewardPool.rewardToken();
        rewardTokens[extraRewardsLength] = address(rewardToken);

        // Add in the default token
        if (defaultToken != address(0)) {
            rewardTokens[totalLength - 1] = defaultToken;
        }

        // claim rewards
        if (!rewardPool.getReward(account, true)) {
            revert RewardAdapter.ClaimRewardsFailed();
        }

        // Get the amount we are reporting as the claimed amount.
        // Note, this may include a balance of the token already held by the account
        for (uint256 i = 0; i < totalLength; ++i) {
            if (i < extraRewardsLength) {
                rewardTokens[i] = address(IBaseRewardPool(rewardPool.extraRewards(i)).rewardToken());
            }

            // Some tokens we want to be sure aren't transferred out or reported as rewards
            // These are the "trackedTokens" from the DestinationVault and usually just include the LP token
            // It would be odd for the LP token to also be a reward token but still have to check
            if (trackedTokens.contains(rewardTokens[i])) {
                rewardTokens[i] = address(0);
            }

            if (rewardTokens[i] != address(0)) {
                (amountsClaimed[i], rewardTokens[i]) = safeRewardTokenBalanceOf(rewardTokens[i], account);

                // We don't need to report on it if we don't have a balance
                // slither-disable-next-line incorrect-equality
                if (amountsClaimed[i] == 0) {
                    rewardTokens[i] = address(0);
                }

                if (sendTo != address(this) && amountsClaimed[i] > 0 && rewardTokens[i] != address(0)) {
                    IERC20(rewardTokens[i]).safeTransfer(sendTo, amountsClaimed[i]);
                }
            }
        }

        RewardAdapter.emitRewardsClaimed(rewardTokens, amountsClaimed);

        return (amountsClaimed, rewardTokens);
    }

    /// @notice Get the balance of a reward token taking into stash tokens on Convex
    /// @dev Sometimes a reward token is a stash token. Sometimes a stash token actually has rewards that are received.
    /// Sometimes they don't. We're working through the scenarios here.
    /// @param token The ERC20 to check balance of
    /// @param wallet The wallet to check the balance of
    /// @return resultAmount Balance of the token or 0 in case of invalid query
    /// @return resultToken Actual reward token
    function safeRewardTokenBalanceOf(
        address token,
        address wallet
    ) private view returns (uint256 resultAmount, address resultToken) {
        resultAmount = IERC20(token).balanceOf(wallet);

        // If we end up with zero here then one of these scenarios is true:
        // - Our balance could just very well be 0
        // - This is a Convex stash token that is hard coded to return 0 for anything but the gauge
        // Either way, if we have 0, lets check to see if this is a Convex stash token which may have rewards
        // and we check by trying to query the token() and getting the balance of the underlyer
        // slither-disable-next-line incorrect-equality
        if (resultAmount == 0) {
            // Try for Convex stash token
            (bool successToken, bytes memory dataToken) = token.staticcall(abi.encodeCall(IConvexStashToken.token, ()));

            if (successToken && dataToken.length > 0) {
                address stashToken = abi.decode(dataToken, (address));

                (bool isInvalidResult, bytes memory isInvalidData) =
                    token.staticcall(abi.encodeCall(IConvexStashToken.isInvalid, ()));

                if (isInvalidResult && isInvalidData.length > 0 && !abi.decode(isInvalidData, (bool))) {
                    resultToken = stashToken;
                    resultAmount = IERC20(stashToken).balanceOf(wallet);
                }
            }
        } else {
            resultToken = token;
        }
    }
}
//slither-disable-end missing-inheritance,low-level-calls
