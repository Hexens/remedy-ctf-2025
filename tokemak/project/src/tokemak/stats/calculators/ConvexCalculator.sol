// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable var-name-mixedcase

import { Errors } from "src/tokemak/utils/Errors.sol";
import { ConvexRewards } from "src/tokemak/libs/ConvexRewards.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ITokenWrapper } from "src/tokemak/interfaces/external/convex/ITokenWrapper.sol";
import { IConvexBooster } from "src/tokemak/interfaces/external/convex/IConvexBooster.sol";
import { IBaseRewardPool } from "src/tokemak/interfaces/external/convex/IBaseRewardPool.sol";
import { IncentiveCalculatorBase } from "src/tokemak/stats/calculators/base/IncentiveCalculatorBase.sol";

contract ConvexCalculator is IncentiveCalculatorBase {
    address public immutable BOOSTER;

    constructor(ISystemRegistry _systemRegistry, address _booster) IncentiveCalculatorBase(_systemRegistry) {
        Errors.verifyNotZero(_booster, "_booster");

        // slither-disable-next-line missing-zero-check
        BOOSTER = _booster;
    }

    /// @dev initializer protection is on the base class
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) public virtual override {
        super.initialize(dependentAprIds, initData);

        // slither-disable-next-line unused-return
        (address convexResolvedLpToken,,,,,) = IConvexBooster(BOOSTER).poolInfo(rewarder.pid());

        // Checking for a misconfiguration between the rewarder and the supplied params
        if (convexResolvedLpToken != lpToken) {
            revert Errors.InvalidParam("convexResolvedLpToken");
        }
    }

    /// @inheritdoc IncentiveCalculatorBase
    function getPlatformTokenMintAmount(
        address _platformToken,
        uint256 _annualizedReward
    ) public view override returns (uint256) {
        return ConvexRewards.getCVXMintAmount(_platformToken, _annualizedReward);
    }

    /// @notice If the pool id is >= 151, then it is a stash token that should be unwrapped:
    /// Ref: https://docs.convexfinance.com/convexfinanceintegration/baserewardpool
    function resolveRewardToken(
        address extraRewarder
    ) public view override returns (address rewardToken) {
        rewardToken = address(IBaseRewardPool(extraRewarder).rewardToken());

        // Taking PID from base rewarder
        if (rewarder.pid() >= 151) {
            ITokenWrapper reward = ITokenWrapper(rewardToken);
            // Retrieving the actual token value if token is valid
            rewardToken = reward.isInvalid() ? address(0) : reward.token();
        }
    }
}
