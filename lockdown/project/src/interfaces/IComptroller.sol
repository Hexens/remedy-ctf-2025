// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

/**
 * @title IComptroller.sol
 *
 * @notice Interface to provide Compound v2 Comptroller functionality
 * see https://docs.compound.finance/v2/comptroller/
 */

interface IComptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
}