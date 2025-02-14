// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ICERC20.sol
 *
 * @notice Interface to provide Compound v2 cToken functionality
 * see https://docs.compound.finance/v2/ctokens/
 */

interface ICERC20 is IERC20 {
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function mint(uint256) external returns (uint256);
    function exchangeRateCurrent() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function underlying() external view returns (address);
    function balanceOfUnderlying(address owner) external  returns (uint);
}