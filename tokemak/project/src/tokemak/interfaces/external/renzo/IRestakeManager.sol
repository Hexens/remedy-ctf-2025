// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IRestakeManager {
    /// @dev This function calculates the TVLs for each operator delegator by individual token, total for each OD, and
    /// total for the protocol.
    /// @return operatorDelegatorTokenTVLs Each OD's TVL indexed by operatorDelegators array by collateralTokens array
    /// @return operatorDelegatorTVLs Each OD's Total TVL in order of operatorDelegators array
    /// @return totalTVL The total TVL across all operator delegators.
    function calculateTVLs() external view returns (uint256[][] memory, uint256[] memory, uint256);
}
