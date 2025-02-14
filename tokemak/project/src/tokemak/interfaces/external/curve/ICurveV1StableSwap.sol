// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase, var-name-mixedcase
// slither-disable-start naming-convention
interface ICurveV1StableSwap {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external payable;

    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external payable;

    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external payable;

    function remove_liquidity(uint256 amount, uint256[2] memory min_amounts) external;

    function remove_liquidity(uint256 amount, uint256[3] memory min_amounts) external;

    function remove_liquidity(uint256 amount, uint256[4] memory min_amounts) external;

    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount) external;

    function calc_withdraw_one_coin(uint256 token_amount, uint256 i) external returns (uint256);

    function coins(
        uint256 i
    ) external view returns (address);

    function balanceOf(
        address account
    ) external returns (uint256);

    function exchange(
        int128 sellTokenIndex,
        int128 buyTokenIndex,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) external payable returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function withdraw_admin_fees() external;

    function owner() external view returns (address);

    function admin_balances(
        uint256 i
    ) external view returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    function fee() external view returns (uint256);
}
// slither-disable-end naming-convention
