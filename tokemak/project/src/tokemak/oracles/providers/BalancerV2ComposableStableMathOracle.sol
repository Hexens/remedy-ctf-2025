// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";
import { IBasePool } from "src/tokemak/interfaces/external/balancer/IBasePool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BalancerUtilities } from "src/tokemak/libs/BalancerUtilities.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

import {
    BalancerV2BaseStableMathOracle,
    ISystemRegistry,
    IVault
} from "src/tokemak/oracles/providers/base/BalancerV2BaseStableMathOracle.sol";

/// @title An oracle for Balancer composablestable pools using stablemath for calculations
contract BalancerV2ComposableStableMathOracle is BalancerV2BaseStableMathOracle {
    function getDescription() external pure override returns (string memory) {
        return "balV2ComposableStableMath";
    }

    constructor(IVault _vault, ISystemRegistry _registry) BalancerV2BaseStableMathOracle(_vault, _registry) { }

    function _getTotalSupply(
        address pool
    ) internal view override returns (uint256) {
        return IBalancerComposableStablePool(pool).getActualSupply();
    }

    function _getPoolTokens(
        address pool
    )
        internal
        view
        override
        returns (IERC20[] memory poolTokens, uint256[] memory rawBalances, bytes memory extraData)
    {
        if (!BalancerUtilities.isComposablePool(pool)) revert Errors.InvalidConfiguration();

        (poolTokens, rawBalances) = BalancerUtilities._getComposablePoolTokensSkipBpt(vault, pool);
        extraData = abi.encode(BalancerV2StableOracleData({ pool: pool, rawBalances: rawBalances }));
    }

    function _getScalingFactors(
        address pool
    ) internal view override returns (uint256[] memory scalingFactorsNoBpt) {
        uint256 bptIdx = IBalancerComposableStablePool(pool).getBptIndex();
        uint256[] memory scalingFactors = IBasePool(pool).getScalingFactors();

        uint256 len = scalingFactors.length;
        scalingFactorsNoBpt = new uint256[](len - 1);

        uint256 scalingFactorsNoBptIndex = 0;
        for (uint256 i = 0; i < len;) {
            if (i == bptIdx) {
                unchecked {
                    ++i;
                }
                continue;
            }

            scalingFactorsNoBpt[scalingFactorsNoBptIndex] = scalingFactors[i];
            unchecked {
                ++i;
                ++scalingFactorsNoBptIndex;
            }
        }
    }
}
