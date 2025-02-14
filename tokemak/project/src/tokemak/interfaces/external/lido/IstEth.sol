// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IstEth {
    function submit(
        address _referral
    ) external payable returns (uint256);

    function decimals() external view returns (uint8);

    /**
     * @notice Gets the amount of underlyer ETH by share
     * @dev returns answer in 18 decimals of precision.
     */
    function getPooledEthByShares(
        uint256
    ) external view returns (uint256);
}
