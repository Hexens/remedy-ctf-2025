// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IBooster } from "src/tokemak/interfaces/external/aura/IBooster.sol";

// reference: https://docs.aura.finance/aura/usdaura/distribution#aura-vs-bal-lp-rewards
library AuraRewards {
    uint256 internal constant EMISSIONS_MAX_SUPPLY = 5e25; // 50m
    uint256 internal constant INIT_MINT_AMOUNT = 5e25; // 50m
    uint256 internal constant TOTALCLIFFS = 500;
    uint256 internal constant REDUCTIONPERCLIFF = EMISSIONS_MAX_SUPPLY / TOTALCLIFFS;

    /**
     * @notice Calculates the amount of AURA that is minted given the amount of BAL earned
     * @param auraToken address for AURA token
     * @param balEarned the amount of BAL reward that was earned
     */
    function getAURAMintAmount(
        address auraToken,
        address booster,
        address rewarder,
        uint256 balEarned
    ) internal view returns (uint256) {
        uint256 auraSupply = IERC20(auraToken).totalSupply();
        uint256 rewardMultiplier = IBooster(booster).getRewardMultipliers(rewarder);
        balEarned = balEarned * rewardMultiplier / IBooster(booster).REWARD_MULTIPLIER_DENOMINATOR();

        // if no AURA has been minted, pre-mine the same amount as the provided BAL
        if (auraSupply == 0 || balEarned == 0) return 0;

        // After AuraMinter.inflationProtectionTime (June 5, 2025) has passed,
        // minterMinted may not be 0. Excluded from emissionsMinted at this time.
        uint256 emissionsMinted = auraSupply - INIT_MINT_AMOUNT;
        uint256 cliff = emissionsMinted / REDUCTIONPERCLIFF;
        if (cliff < TOTALCLIFFS) {
            uint256 reduction = (((TOTALCLIFFS - cliff) * 5 / 2) + 700);
            uint256 auraEarned = balEarned * reduction / TOTALCLIFFS;
            uint256 amtTillMax = EMISSIONS_MAX_SUPPLY - emissionsMinted;
            if (auraEarned > amtTillMax) {
                auraEarned = amtTillMax;
            }

            return auraEarned;
        }

        return 0;
    }
}
