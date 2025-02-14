// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { Errors } from "src/tokemak/utils/Errors.sol";
import { WithdrawalQueue } from "src/tokemak/strategy/WithdrawalQueue.sol";
import { StructuredLinkedList } from "src/tokemak/strategy/StructuredLinkedList.sol";
import { IDestinationVault } from "src/tokemak/interfaces/vault/IDestinationVault.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IDestinationVaultRegistry } from "src/tokemak/interfaces/vault/IDestinationVaultRegistry.sol";

library AutopoolDestinations {
    using EnumerableSet for EnumerableSet.AddressSet;
    using WithdrawalQueue for StructuredLinkedList.List;

    event DestinationVaultAdded(address destination);
    event DestinationVaultRemoved(address destination);
    event WithdrawalQueueSet(address[] destinations);
    event AddedToRemovalQueue(address destination);
    event RemovedFromRemovalQueue(address destination);

    error TooManyDeployedDestinations();

    /// @notice Maximum amount of destinations we can be deployed to a given time
    uint256 public constant MAX_DEPLOYED_DESTINATIONS = 50;

    /// @notice Remove, or queue to remove if necessary, destinations from the vault
    /// @dev No need to handle withdrawal queue as it will be popped once it hits balance 0 in withdraw or rebalance.
    /// Debt report queue is handled the same way
    /// @param removalQueue Destinations that queued for removal in the vault
    /// @param destinations Full list of destinations from the vault
    /// @param _destinations Destinations to remove
    function removeDestinations(
        EnumerableSet.AddressSet storage removalQueue,
        EnumerableSet.AddressSet storage destinations,
        address[] calldata _destinations
    ) external {
        for (uint256 i = 0; i < _destinations.length; ++i) {
            address dAddress = _destinations[i];
            IDestinationVault destination = IDestinationVault(dAddress);

            // remove from main list (NOTE: done here so balance check below doesn't explode if address is invalid)
            if (!destinations.remove(dAddress)) {
                revert Errors.ItemNotFound();
            }

            if (destination.balanceOf(address(this)) > 0 && !removalQueue.contains(dAddress)) {
                // we still have funds in it! move it to removalQueue for rebalancer to handle it later
                // slither-disable-next-line unused-return
                removalQueue.add(dAddress);

                emit AddedToRemovalQueue(dAddress);
            }

            emit DestinationVaultRemoved(dAddress);
        }
    }

    /// @notice Add a destination to the vault
    /// @dev No need to add to debtReport and withdrawal queue from the vault as the rebalance will take care of that
    /// @param removalQueue Destinations that queued for removal in the vault
    /// @param destinations Full list of destinations from the vault
    /// @param _destinations New destinations to add
    /// @param systemRegistry System registry reference for the vault
    function addDestinations(
        EnumerableSet.AddressSet storage removalQueue,
        EnumerableSet.AddressSet storage destinations,
        address[] calldata _destinations,
        ISystemRegistry systemRegistry
    ) external {
        IDestinationVaultRegistry destinationRegistry = systemRegistry.destinationVaultRegistry();

        uint256 numDestinations = _destinations.length;
        if (numDestinations == 0) {
            revert Errors.InvalidParams();
        }

        address dAddress;
        for (uint256 i = 0; i < numDestinations; ++i) {
            dAddress = _destinations[i];

            // Address must be setup in our registry
            if (dAddress == address(0) || !destinationRegistry.isRegistered(dAddress)) {
                revert Errors.InvalidAddress(dAddress);
            }

            // Don't allow duplicates
            if (!destinations.add(dAddress)) {
                revert Errors.ItemExists();
            }

            // A destination could be queued for removal but we decided
            // to keep it
            // slither-disable-next-line unused-return
            removalQueue.remove(dAddress);

            emit DestinationVaultAdded(dAddress);
        }
    }

    /// @notice Ensure a destination is in the queues it should be after a rebalance or debt report
    /// @param destination The destination to manage
    /// @param destinationIn Whether the destination was moved into, true, or out of, false.
    function _manageQueuesForDestination(
        address destination,
        bool destinationIn,
        StructuredLinkedList.List storage withdrawalQueue,
        StructuredLinkedList.List storage debtReportQueue,
        EnumerableSet.AddressSet storage removalQueue
    ) external {
        // The vault itself, when we are moving idle around, should never be
        // in the queues.
        if (destination != address(this)) {
            // If we have a balance, we need to continue to report on it
            if (IDestinationVault(destination).balanceOf(address(this)) > 0) {
                // For debt reporting, we just updated the values so we can put
                // it at the end of the queue.
                debtReportQueue.addToTail(destination);

                // Debt reporting queue is a proxy for destinations we are deployed to
                // Easiest to check after doing the add as "addToTail" can move
                // the destination when it already exists. Also, we run this fn for the "out"
                // destination first so we're sure to free the spots we can
                if (debtReportQueue.sizeOf() > MAX_DEPLOYED_DESTINATIONS) {
                    revert TooManyDeployedDestinations();
                }

                // For withdraws, if we moved into the position then we want to put it
                // at the end of the queue so we don't exit from our higher projected
                // apr positions first. If we exited, that means its a lower apr
                // and we want to continue to exit via user withdrawals so put it at the top
                if (destinationIn) withdrawalQueue.addToTail(destination);
                else withdrawalQueue.addToHead(destination);
            } else {
                // If we no longer have a balance we don't need to continue to report
                // on it and we also have nothing to withdraw from it

                // Audit update: https://github.com/Tokemak/v2-core/issues/657
                // We don't remove the destination from the debt queue here as it
                // still might have unclaimed rewards.
                withdrawalQueue.popAddress(destination);

                if (removalQueue.remove(destination)) {
                    emit RemovedFromRemovalQueue(destination);
                }
            }
        }
    }
}
