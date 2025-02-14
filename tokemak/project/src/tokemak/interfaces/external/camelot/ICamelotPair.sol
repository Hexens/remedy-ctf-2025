// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICamelotPair {
    /// @notice Gets reserves of Camelot pool.
    // slither-disable-start similar-names
    function getReserves()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent);
    // slither-disable-end similar-names
}
