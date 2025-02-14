// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

interface ICurveResolver {
    /// @notice Resolve details of a Curve pool regardless of type or version
    /// @dev This resolves tokens without unwrapping to underlying in the case of meta pools.
    /// @param poolAddress pool address to lookup
    /// @return tokens tokens that make up the pool
    /// @return numTokens the number of tokens. tokens are not unwrapped.
    /// @return isStableSwap is this a StableSwap pool. false = CryptoSwap
    function resolve(
        address poolAddress
    ) external view returns (address[8] memory tokens, uint256 numTokens, bool isStableSwap);

    /// @notice Resolve details of a Curve pool regardless of type or version
    /// @dev This resolves tokens without unwrapping to underlying in the case of meta pools.
    /// @dev Use the isStableSwap value to differentiate between StableSwap (V1) and CryptoSwap (V2) pools.
    /// @param poolAddress pool address to lookup
    /// @return tokens tokens that make up the pool
    /// @return numTokens the number of tokens. tokens are not unwrapped
    /// @return lpToken lp token of the pool
    /// @return isStableSwap is this a StableSwap pool. false = CryptoSwap
    function resolveWithLpToken(
        address poolAddress
    ) external view returns (address[8] memory tokens, uint256 numTokens, address lpToken, bool isStableSwap);

    /// @notice Get the lp token of a Curve pool
    /// @param poolAddress pool address to lookup
    function getLpToken(
        address poolAddress
    ) external view returns (address);

    /// @notice Get the reserves of a Curve pools' tokens
    /// @dev Actual balances length might differ from 8 and should be verified by the caller
    /// @param poolAddress pool address to lookup
    /// @return balances reserves of the pool tokens
    function getReservesInfo(
        address poolAddress
    ) external view returns (uint256[8] memory balances);
}
