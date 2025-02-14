// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

/// @title EWMA pricing for incentive tokens
interface IIncentivesPricingStats {
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event TokenSnapshot(
        address indexed token,
        uint40 lastSnapshot,
        uint256 fastFilterPrice,
        uint256 slowFilterPrice,
        uint256 initCount,
        bool initComplete
    );

    error TokenAlreadyRegistered(address token);
    error TokenNotFound(address token);
    error IncentiveTokenPriceStale(address token);
    error TokenSnapshotNotReady(address token);

    struct TokenSnapshotInfo {
        uint40 lastSnapshot;
        bool _initComplete;
        uint8 _initCount;
        uint256 _initAcc;
        uint256 fastFilterPrice;
        uint256 slowFilterPrice;
    }

    /// @notice add a token to snapshot
    /// @dev the token must be configured in the RootPriceOracle before adding here
    /// @param token the address of the token to add
    function setRegisteredToken(
        address token
    ) external;

    /// @notice remove a token from being snapshot
    /// @param token the address of the token to remove
    function removeRegisteredToken(
        address token
    ) external;

    /// @notice get the addresses for all currently registered tokens
    /// @return tokens all of the registered token addresses
    function getRegisteredTokens() external view returns (address[] memory tokens);

    /// @notice get all of the registered tokens with the latest snapshot info
    /// @return tokenAddresses token addresses in the same order as info
    /// @return info a list of snapshot info for the tokens
    function getTokenPricingInfo()
        external
        view
        returns (address[] memory tokenAddresses, TokenSnapshotInfo[] memory info);

    /// @notice update the snapshot for the specified tokens
    /// @dev if a token is not ready to be snapshot the entire call will fail
    function snapshot(
        address[] calldata tokensToSnapshot
    ) external;

    /// @notice get the latest prices for an incentive token. Reverts if token is not registered
    /// @return fastPrice the price based on the faster filter (weighted toward current prices)
    /// @return slowPrice the price based on the slower filter (weighted toward older prices, relative to fast)
    function getPrice(address token, uint40 staleCheck) external view returns (uint256 fastPrice, uint256 slowPrice);

    /// @notice get the latest prices for an incentive token or zero if the token is not registered
    /// @return fastPrice the price based on the faster filter (weighted toward current prices)
    /// @return slowPrice the price based on the slower filter (weighted toward older prices, relative to fast)
    function getPriceOrZero(
        address token,
        uint40 staleCheck
    ) external view returns (uint256 fastPrice, uint256 slowPrice);
}
