// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { ICurveResolver } from "src/tokemak/interfaces/utils/ICurveResolver.sol";
import { ICurveMetaRegistry } from "src/tokemak/interfaces/external/curve/ICurveMetaRegistry.sol";
import { IPool } from "src/tokemak/interfaces/external/curve/IPool.sol";

contract CurveResolverMainnet is ICurveResolver {
    ICurveMetaRegistry public immutable curveMetaRegistry;

    error CouldNotResolve(address poolAddress);

    constructor(
        ICurveMetaRegistry _curveMetaRegistry
    ) {
        Errors.verifyNotZero(address(_curveMetaRegistry), "_curveMetaRegistry");

        curveMetaRegistry = _curveMetaRegistry;
    }

    /// @inheritdoc ICurveResolver
    function resolve(
        address poolAddress
    ) public view returns (address[8] memory tokens, uint256 numTokens, bool isStableSwap) {
        Errors.verifyNotZero(poolAddress, "poolAddress");

        // If a pool is not showing up in the registry, this will revert
        try curveMetaRegistry.get_coins(poolAddress) returns (address[8] memory retTokens) {
            tokens = retTokens;
            numTokens = curveMetaRegistry.get_n_coins(poolAddress);
        } catch {
            // We have to try other means to get the information
            do {
                //slither-disable-start low-level-calls,missing-zero-check
                (bool success, bytes memory retData) = poolAddress.staticcall(abi.encodeCall(IPool.coins, (numTokens)));
                //slither-disable-end low-level-calls,missing-zero-check
                if (!success) {
                    break;
                }
                if (retData.length > 0) {
                    tokens[numTokens] = abi.decode(retData, (address));
                }
                if (tokens[numTokens] == address(0)) {
                    break;
                }
                unchecked {
                    ++numTokens;
                }
            } while (true);
        }

        if (numTokens == 0) {
            revert CouldNotResolve(poolAddress);
        }

        isStableSwap = _isStableSwap(poolAddress);
    }

    /// @inheritdoc ICurveResolver
    function resolveWithLpToken(
        address poolAddress
    ) external view returns (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap) {
        (tokens, numTokens, isStableSwap) = resolve(poolAddress);
        lpToken = getLpToken(poolAddress);
    }

    /// @inheritdoc ICurveResolver
    function getLpToken(
        address poolAddress
    ) public view returns (address) {
        // If a pool is not showing up in the registry, this will revert
        try curveMetaRegistry.get_lp_token(poolAddress) returns (address lpToken) {
            return lpToken;
        } catch {
            //slither-disable-start low-level-calls,missing-zero-check
            // We have to try other means to get the information
            (bool success, bytes memory retData) = poolAddress.staticcall(abi.encodeCall(IPool.totalSupply, ()));
            if (success && retData.length > 0) {
                // If the pool address has a totalSupply() call then pool is lpToken
                return poolAddress;
            }

            (success, retData) = poolAddress.staticcall(abi.encodeCall(IPool.lp_token, ()));
            if (success && retData.length > 0) {
                return abi.decode(retData, (address));
            }

            (success, retData) = poolAddress.staticcall(abi.encodeCall(IPool.token, ()));
            if (success && retData.length > 0) {
                return abi.decode(retData, (address));
            }
            //slither-disable-end low-level-calls,missing-zero-check
        }

        revert CouldNotResolve(poolAddress);
    }

    /// @inheritdoc ICurveResolver
    function getReservesInfo(
        address poolAddress
    ) external view returns (uint256[8] memory ret) {
        Errors.verifyNotZero(poolAddress, "poolAddress");

        // If a pool is not showing up in the registry, this will revert
        try curveMetaRegistry.get_balances(poolAddress) returns (uint256[8] memory retBalances) {
            return retBalances;
        } catch {
            // We have to try other means to get the information
            uint256 i = 0;
            do {
                // No newer pools use the balances(int256) interface and we won't be targeting the older ones
                //slither-disable-start low-level-calls,missing-zero-check
                (bool success, bytes memory retData) = poolAddress.staticcall(abi.encodeCall(IPool.balances, i));
                //slither-disable-end low-level-calls,missing-zero-check
                if (success && retData.length > 0) {
                    ret[i] = abi.decode(retData, (uint256));
                } else {
                    break;
                }

                unchecked {
                    ++i;
                }
            } while (i < 8);

            if (i == 0) {
                revert CouldNotResolve(poolAddress);
            }
        }
    }

    function _isStableSwap(
        address pool
    ) private view returns (bool) {
        // Using the presence of a gamma() fn as an indicator of pool type
        // Zero check for the poolAddress is above
        // slither-disable-start low-level-calls,missing-zero-check,unchecked-lowlevel
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = pool.staticcall(abi.encodeCall(IPool.gamma, ()));
        // slither-disable-end low-level-calls,missing-zero-check,unchecked-lowlevel

        return !success;
    }
}
