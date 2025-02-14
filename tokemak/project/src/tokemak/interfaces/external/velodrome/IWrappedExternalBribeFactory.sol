// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWrappedExternalBribeFactory {
    function oldBribeToNew(
        address existingBribe
    ) external view returns (address);
}
