// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPool } from "src/tokemak/interfaces/external/curve/IPool.sol";

/* solhint-disable func-name-mixedcase, var-name-mixedcase */
interface ICryptoSwapPool is IPool {
    function token() external returns (address);

    // slither-disable-start naming-convention
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external payable returns (uint256);

    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external payable returns (uint256);

    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external payable returns (uint256);

    function remove_liquidity(uint256 amount, uint256[2] memory min_amounts) external;

    function remove_liquidity(uint256 amount, uint256[3] memory min_amounts) external;

    function remove_liquidity(uint256 amount, uint256[4] memory min_amounts) external;

    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount) external;
    // slither-disable-end naming-convention

    function get_virtual_price() external returns (uint256);

    function claim_admin_fees() external;
}
