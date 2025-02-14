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
import { ISystemRegistryL2 } from "src/tokemak/interfaces/ISystemRegistryL2.sol";
import { ISequencerChecker } from "src/tokemak/interfaces/security/ISequencerChecker.sol";

// solhint-disable max-states-count

/// @notice Root contract of the system instance on L2.
/// @dev All contracts in this instance of the system should be reachable from this contract
contract SystemRegistryL2 is SystemRegistryBase, ISystemRegistryL2 {
    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice TOKE token
    IERC20Metadata public toke;

    /// =====================================================
    /// Private Vars
    /// =====================================================

    ISequencerChecker private _sequencerChecker;

    /// =====================================================
    /// Events
    /// =====================================================

    event TokeSet(address newAddress);
    event SequencerCheckerSet(address newSequencerChecker);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(address _toke, address _weth) SystemRegistryBase(_weth) {
        Errors.verifyNotZero(address(_toke), "_toke");

        toke = IERC20Metadata(_toke);
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Set the Toke for this instance of the system
    /// @param newToke Address of the Toke contract
    function setToke(
        address newToke
    ) external onlyOwner {
        Errors.verifyNotZero(newToke, "newToke");

        if (address(toke) == newToke) {
            revert DuplicateSet(newToke);
        }

        toke = IERC20Metadata(newToke);

        emit TokeSet(newToke);

        _verifySystemsAgree(address(newToke));
    }

    /// @notice Set sequencer checker instance for this system
    /// @dev Value can be replaced
    /// @dev This is expected to be a zero address on an L2 that does not use a sequencer
    /// @param checker Address of the sequencer checker
    function setSequencerChecker(
        address checker
    ) external onlyOwner {
        Errors.verifyNotZero(checker, "checker");

        if (checker == address(_sequencerChecker)) {
            revert DuplicateSet(checker);
        }

        emit SequencerCheckerSet(checker);

        _sequencerChecker = ISequencerChecker(checker);

        _verifySystemsAgree(checker);
    }

    function sequencerChecker() external view returns (ISequencerChecker) {
        return _sequencerChecker;
    }
}
