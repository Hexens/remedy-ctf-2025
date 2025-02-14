// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./LuckyToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Challenge {
    
    address public immutable PLAYER;
    LuckyToken public immutable TOKEN;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(address player) payable {
        PLAYER = player;
        TOKEN = new LuckyToken{value: 10 ether}(1010101, address(msg.sender));
        TOKEN.openTrading();
    }

    function isSolved() external view returns (bool) {
        return IERC20(WETH).balanceOf(TOKEN.uniswapV2Pair()) < 1 ether;
    }
}