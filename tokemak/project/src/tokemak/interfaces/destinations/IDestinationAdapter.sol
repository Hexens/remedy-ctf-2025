// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDestinationAdapter
 * @dev This is a super-interface to unify different types of adapters to be registered in Destination Registry.
 *      Specific interface type is defined by extending from this interface.
 */
interface IDestinationAdapter {
    error MustBeMoreThanZero();
    error ArraysLengthMismatch();
    error BalanceMustIncrease();
    error MinLpAmountNotReached();
    error LpTokenAmountMismatch();
    error NoNonZeroAmountProvided();
    error InvalidBalanceChange();
    error InvalidAddress(address);
}
