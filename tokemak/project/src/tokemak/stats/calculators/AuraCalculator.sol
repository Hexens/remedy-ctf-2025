// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable var-name-mixedcase

import { Errors } from "src/tokemak/utils/Errors.sol";
import { AuraRewards } from "src/tokemak/libs/AuraRewards.sol";
import { IBooster } from "src/tokemak/interfaces/external/aura/IBooster.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IAuraStashToken } from "src/tokemak/interfaces/external/aura/IAuraStashToken.sol";
import { IBaseRewardPool } from "src/tokemak/interfaces/external/convex/IBaseRewardPool.sol";
import { IncentiveCalculatorBase } from "src/tokemak/stats/calculators/base/IncentiveCalculatorBase.sol";

contract AuraCalculator is IncentiveCalculatorBase {
    address public immutable BOOSTER;

    constructor(ISystemRegistry _systemRegistry, address _booster) IncentiveCalculatorBase(_systemRegistry) {
        Errors.verifyNotZero(_booster, "_booster");

        // slither-disable-next-line missing-zero-check
        BOOSTER = _booster;
    }

    /// @dev initializer protection is on the base class
    function initialize(bytes32[] calldata dependentAprIds, bytes calldata initData) public virtual override {
        super.initialize(dependentAprIds, initData);

        IBooster.PoolInfo memory poolInfo = IBooster(BOOSTER).poolInfo(rewarder.pid());

        // Checking for a misconfiguration between the rewarder and the supplied params
        if (poolInfo.lptoken != lpToken) {
            revert Errors.InvalidParam("lptoken");
        }
    }

    /// @inheritdoc IncentiveCalculatorBase
    function getPlatformTokenMintAmount(
        address _platformToken,
        uint256 _annualizedReward
    ) public view virtual override returns (uint256) {
        return AuraRewards.getAURAMintAmount(_platformToken, BOOSTER, address(rewarder), _annualizedReward);
    }

    /// @dev For the Aura implementation every `rewardToken()` is a stash token
    function resolveRewardToken(
        address extraRewarder
    ) public view override returns (address rewardToken) {
        IERC20 rewardTokenErc = IBaseRewardPool(extraRewarder).rewardToken();
        IAuraStashToken stashToken = IAuraStashToken(address(rewardTokenErc));
        if (stashToken.isValid()) {
            rewardToken = stashToken.baseToken();
        }
    }
}
