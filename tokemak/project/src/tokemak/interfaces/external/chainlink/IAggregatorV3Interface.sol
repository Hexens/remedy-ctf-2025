// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAggregatorV3Interface {
    /// @notice Returns decimal precision of price feed.
    function decimals() external view returns (uint8);

    /**
     * @return roundId The round Id.
     * @return answer The price.
     * @return startedAt Timestamp when the round started.
     * @return updatedAt Timestamp when the round ended.
     * @return answeredInRound Round Id of round when answer was computed.
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Returns address of aggregator contract.  Used to set min and max price when registering oracle.
    function aggregator() external view returns (address);
}
