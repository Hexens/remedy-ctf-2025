// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";

import { ScalingHelpers } from "src/tokemak/external/balancer/ScalingHelpers.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

import {
    BalancerBaseStableMathOracle, ISystemRegistry
} from "src/tokemak/oracles/providers/base/BalancerBaseStableMathOracle.sol";

/// @title A base oracle for common Balancer V2 functionalities
abstract contract BalancerV2BaseStableMathOracle is BalancerBaseStableMathOracle {
    IVault public immutable vault;

    struct BalancerV2StableOracleData {
        address pool;
        uint256[] rawBalances;
    }

    constructor(IVault _vault, ISystemRegistry _registry) BalancerBaseStableMathOracle(_registry) {
        Errors.verifyNotZero(address(_vault), "_vault");

        vault = _vault;
    }

    /// @inheritdoc BalancerBaseStableMathOracle
    function _getLiveBalancesAndScalingFactors(
        bytes memory data
    ) internal view override returns (uint256[] memory scaledBalances, uint256[] memory scalingFactors) {
        BalancerV2StableOracleData memory decodedData = abi.decode(data, (BalancerV2StableOracleData));

        scalingFactors = _getScalingFactors(decodedData.pool);

        uint256[] memory rawBalances = decodedData.rawBalances;
        uint256 length = rawBalances.length;

        Errors.verifyArrayLengths(length, scalingFactors.length, "rawBalances+scalingFactors");

        scaledBalances = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            scaledBalances[i] = ScalingHelpers.toScaled18RoundDown(rawBalances[i], scalingFactors[i]);
        }
    }

    /// @notice Gets scaling factors for pool
    /// @param pool Address of pool
    /// @return scalingFactors Scaling factors for tokens in pool
    function _getScalingFactors(
        address pool
    ) internal view virtual returns (uint256[] memory scalingFactors);
}
