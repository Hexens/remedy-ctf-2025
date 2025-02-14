// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "src/Challenge.sol";
import "src/LFGStaker.sol";
import "src/tokemak/SystemRegistry.sol";
import "src/tokemak/vault/AutopoolETH.sol";
import "src/tokemak/interfaces/utils/IWETH9.sol";

contract Challenge {

    address public constant SYSTEM_REGISTRY = 0x2218F90A98b0C070676f249EF44834686dAa4285;
    address public constant AUTOPOOL_ETH    = 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56;
    address public constant WETH            = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public immutable PLAYER;
    address public immutable LFG_STAKER;

    constructor(address player) {
        PLAYER = player;
        LFG_STAKER = address(new LFGStaker(SystemRegistry(SYSTEM_REGISTRY), AutopoolETH(AUTOPOOL_ETH)));
    }

    function isSolved() external view returns (bool) {
        return AutopoolETH(AUTOPOOL_ETH).balanceOf(LFG_STAKER) < 0.1 ether;
    }
}