// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase

interface ICurveV2Swap {
    function coins(
        uint256 i
    ) external view returns (address);

    function exchange(
        uint256 sellTokenIndex,
        uint256 buyTokenIndex,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) external payable returns (uint256);

    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);

    function fee() external view returns (uint256);
}
