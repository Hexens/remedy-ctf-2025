// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {LockMarketplace} from "src/LockMarketplace.sol";
import {LockToken} from "src/LockToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Challenge {

    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant CUSDC = IERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    address public immutable PLAYER;
    address public immutable SYSTEM;

    bool public deployed;
    LockMarketplace public LOCK_MARKETPLACE;
    LockToken public LOCK_TOKEN;
    uint public NFT_ID;

    constructor (address player) {
        PLAYER = player;
        SYSTEM = msg.sender;
    }

    function deploy() external {
        require(msg.sender == SYSTEM);
        require(USDC.balanceOf(address(this)) == 1_000_520e6);
        require(!deployed);
        deployed = true;

        LOCK_MARKETPLACE = new LockMarketplace();
        LOCK_TOKEN = new LockToken(address(LOCK_MARKETPLACE));
        LOCK_MARKETPLACE.initialize(address(LOCK_TOKEN), address(CUSDC), COMPTROLLER);
        LOCK_MARKETPLACE.startMarket(100e6, 30e6, 20e6);
        LOCK_MARKETPLACE.enterMarketWithCUSDC();

        USDC.approve(address(LOCK_MARKETPLACE), 1_000_020e6);
        NFT_ID = LOCK_MARKETPLACE.mintWithUSDC(address(this), 1_000_020e6);
        LOCK_TOKEN.approve(address(LOCK_MARKETPLACE), NFT_ID);
        LOCK_MARKETPLACE.stake(NFT_ID, 1_000_000e6);

        USDC.transfer(PLAYER, 500e6);
    }

    function isSolved() external view returns (bool) {
        return LOCK_MARKETPLACE.isStaked(NFT_ID) &&
            CUSDC.balanceOf(address(LOCK_MARKETPLACE)) < 0.01e18 &&
            USDC.balanceOf(address(LOCK_MARKETPLACE)) < 100e6 &&
            USDC.balanceOf(address(this)) == 0 &&
            USDC.balanceOf(PLAYER) > 1_000_000e6;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        return this.onERC721Received.selector;
    }
}