// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UnstablePool} from "./UnstablePool.sol";
import {PoolToken} from "./PoolToken.sol";
import {WrappedToken} from "./WrappedToken.sol";
import {IERC20} from "src/openzeppelin-contracts/token/ERC20/IERC20.sol";

contract Challenge {
    address public immutable PLAYER;
    UnstablePool public immutable TARGET;
    IERC20 public immutable MAINTOKEN;
    IERC20 public immutable WRAPPEDTOKEN;

    uint256 public initialBalance;

    constructor(address player) payable {
        PLAYER = player;
        MAINTOKEN = IERC20(new PoolToken("stable dollar", "SDT"));
        WRAPPEDTOKEN = IERC20(address(new WrappedToken(address(MAINTOKEN))));
        TARGET = new UnstablePool(address(MAINTOKEN), address(WRAPPEDTOKEN));

        uint256 initialMint = 100_000e18;
        uint256 rewards = 10_000e18;
        PoolToken(address(MAINTOKEN)).mint(address(this), 2 * initialMint + rewards);
        MAINTOKEN.approve(address(WRAPPEDTOKEN), initialMint + rewards);
        WrappedToken(address(WRAPPEDTOKEN)).mint(address(this), initialMint);
        WrappedToken(address(WRAPPEDTOKEN)).addRewards(rewards);
        MAINTOKEN.approve(address(TARGET), type(uint256).max);
        WRAPPEDTOKEN.approve(address(TARGET), type(uint256).max);
        TARGET.swap(UnstablePool.SwapKind.GIVEN_IN, 1, 0, initialMint, address(this), 0);

        initialBalance = curTargetBalance();
    }

    function curTargetBalance() public view returns (uint256) {
        return TARGET.getInvariant();
    }

    function isSolved() public view returns (bool) {
        return curTargetBalance() < (initialBalance / 10);
    }
}
