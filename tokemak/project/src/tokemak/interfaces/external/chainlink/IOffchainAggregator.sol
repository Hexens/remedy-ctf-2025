// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 *  @dev Contract is used to get max and min answers that an oracle can return.  These are used
 *      as circuit breakers by Chainlink to protect against major market fluctuations and
 *      oracle malfunction.
 */
interface IOffchainAggregator {
    /// @notice Minimum answer an oracle can return.
    function minAnswer() external view returns (int192);

    /// @notice Maximum answer an oracle can return.
    function maxAnswer() external view returns (int192);
}
