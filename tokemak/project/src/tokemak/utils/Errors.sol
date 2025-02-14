// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Address } from "openzeppelin-contracts/utils/Address.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";

// solhint-disable max-line-length
library Errors {
    using Address for address;
    ///////////////////////////////////////////////////////////////////
    //                       Set errors
    ///////////////////////////////////////////////////////////////////

    error AccessDenied();
    error ZeroAddress(string paramName);
    error ZeroAmount();
    error InsufficientBalance(address token);
    error AssetNotAllowed(address token);
    error NotImplemented();
    error InvalidAddress(address addr);
    error InvalidParam(string paramName);
    error InvalidParams();
    error UnsafePrice(address token, uint256 spotPrice, uint256 safePrice);
    error AlreadySet(string param);
    error AlreadyRegistered(address param);
    error SlippageExceeded(uint256 expected, uint256 actual);
    error ArrayLengthMismatch(uint256 length1, uint256 length2, string details);

    error ItemNotFound();
    error ItemExists();
    error MissingRole(bytes32 role, address user);
    error RegistryItemMissing(string item);
    error NotRegistered();
    // Used to check storage slot is empty before setting.
    error MustBeZero();
    // Used to check storage slot set before deleting.
    error MustBeSet();

    error ApprovalFailed(address token);
    error FlashLoanFailed(address token, uint256 amount);

    error SystemMismatch(address source1, address source2);

    error InvalidToken(address token);
    error UnreachableError();

    error InvalidSigner(address signer);

    error InvalidChainId(uint256 chainId);

    error SenderMismatch(address recipient, address sender);

    error UnsupportedMessage(bytes32 messageType, bytes message);

    error NotSupported();

    error InvalidConfiguration();

    error InvalidDataReturned();

    function verifyNotZero(address addr, string memory paramName) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress(paramName);
        }
    }

    function verifyNotZero(bytes32 key, string memory paramName) internal pure {
        if (key == bytes32(0)) {
            revert InvalidParam(paramName);
        }
    }

    function verifyNotEmpty(string memory val, string memory paramName) internal pure {
        if (bytes(val).length == 0) {
            revert InvalidParam(paramName);
        }
    }

    function verifyNotZero(uint256 num, string memory paramName) internal pure {
        if (num == 0) {
            revert InvalidParam(paramName);
        }
    }

    function verifySystemsMatch(address component1, address component2) internal view {
        address registry1 =
            abi.decode(component1.functionStaticCall(abi.encodeCall(ISystemComponent.getSystemRegistry, ())), (address));
        address registry2 =
            abi.decode(component2.functionStaticCall(abi.encodeCall(ISystemComponent.getSystemRegistry, ())), (address));

        if (registry1 != registry2) {
            revert SystemMismatch(component1, component2);
        }
    }

    function verifyArrayLengths(uint256 length1, uint256 length2, string memory details) internal pure {
        if (length1 != length2) {
            revert ArrayLengthMismatch(length1, length2, details);
        }
    }
}
