// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IeETH } from "src/tokemak/interfaces/external/etherfi/IeETH.sol";

interface IweETH {
    /// @notice Fetches the amount of weEth respective to the amount of eEth sent in
    /// @param _eETHAmount amount sent in
    /// @return The total number of shares for the specified amount
    function getWeETHByeETH(
        uint256 _eETHAmount
    ) external view returns (uint256);

    /// @notice Fetches the amount of eEth respective to the amount of weEth sent in
    /// @param _weETHAmount amount sent in
    /// @return The total amount for the number of shares sent in
    function getEETHByWeETH(
        uint256 _weETHAmount
    ) external view returns (uint256);

    // Amount of weETH for 1 eETH
    function getRate() external view returns (uint256);

    function eETH() external view returns (IeETH);

    function decimals() external pure returns (uint8);
}
