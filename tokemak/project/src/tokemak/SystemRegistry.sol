// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

//                   ██
//                   ██
//                   ██
//                   ██
//                   ██
//      █████████████████████████████████████████
//                                 ██
//                                 ██
//                                 ██
//                                 ██
//                                 ██

import { Errors } from "src/tokemak/utils/Errors.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SystemRegistryBase } from "src/tokemak/SystemRegistryBase.sol";

// solhint-disable max-states-count

/// @notice Root contract of the system instance on L1.
/// @dev All contracts in this instance of the system should be reachable from this contract
contract SystemRegistry is SystemRegistryBase {
    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    /// @notice TOKE token
    IERC20Metadata public immutable toke;

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(address _toke, address _weth) SystemRegistryBase(_weth) {
        Errors.verifyNotZero(address(_toke), "_toke");

        toke = IERC20Metadata(_toke);
    }
}
