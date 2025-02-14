// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";
import { ISyncSwapper } from "src/tokemak/interfaces/swapper/ISyncSwapper.sol";

/// @dev Reminder from ISyncSwapper: we're adopting an "exact in, variable out" model for all our swaps. This ensures
/// that the entire sellAmount is used, eliminating the need for additional balance checks and refunds. This model is
/// expected to be followed by all swapper implementations to maintain consistency and to optimize for gas efficiency.
abstract contract BaseAdapter is ISyncSwapper {
    ISwapRouter public immutable router;

    constructor(
        address _router
    ) {
        Errors.verifyNotZero(_router, "router");
        router = ISwapRouter(_router);
    }

    /// @dev Reverts if the delegate caller is not the router.
    modifier onlyRouter() {
        if (address(this) != address(router)) revert Errors.AccessDenied();
        _;
    }
}
