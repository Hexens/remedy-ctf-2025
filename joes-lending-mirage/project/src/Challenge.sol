// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {LBFactory, ILBFactory} from "@trader-joe/LBFactory.sol";
import {LBPair, ILBPair, PriceHelper, LiquidityConfigurations} from "@trader-joe/LBPair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MintableERC20, JoeLending} from "src/JoeLending.sol";

contract Challenge {
    address public constant DAI_ORACLE  = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant USDC_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant USDT_ORACLE = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    address public immutable PLAYER;
    ERC20   public immutable USDC;
    ERC20   public immutable USDT;
    ERC20   public immutable USDJ;

    LBFactory   public immutable LB_FACTORY;
    LBPair      public immutable LB_PAIR_IMPL;
    ILBPair     public immutable PAIR_USDT_USDC;
    JoeLending  public immutable JOE_LENDING;

    constructor(address player) {
        PLAYER = player;
        USDC = new MintableERC20("USD Coin", "USDC", 6);
        USDT = new MintableERC20("USD Coin", "USDT", 6);
        USDJ = new MintableERC20("USD Coin", "USDJ", 18);

        // Setup factory
        LB_FACTORY = new LBFactory(address(this), address(this), uint256(5000000000000));
        LB_PAIR_IMPL = new LBPair(ILBFactory(address(LB_FACTORY)));
        LB_FACTORY.setLBPairImplementation(address(LB_PAIR_IMPL));
        LB_FACTORY.setPreset(
            uint16(10),
            uint16(50000),
            uint16(0),
            uint16(0),
            uint16(0),
            uint24(0),
            uint16(0),
            uint24(100000),
            bool(true)
        );
        LB_FACTORY.addQuoteAsset(IERC20(address(USDC)));

        // Setup USDT/USDC pair
        PAIR_USDT_USDC = LB_FACTORY.createLBPair(
            IERC20(address(USDT)), IERC20(address(USDC)), PriceHelper.getIdFromPrice(1, 1), 10
        );

        // Setup Joe Lending
        JOE_LENDING = new JoeLending(USDJ, address(PAIR_USDT_USDC), 12, 12, 0.02e18);
        USDJ.transfer(address(JOE_LENDING), USDJ.balanceOf(address(this)));

        // Setup mint and borrow
        JOE_LENDING.setAssetOracle(USDC, USDC_ORACLE);
        JOE_LENDING.setAssetOracle(USDT, USDT_ORACLE);
        JOE_LENDING.setAssetOracle(USDJ, DAI_ORACLE);
        USDC.transfer(address(PAIR_USDT_USDC), 500e6);
        USDT.transfer(address(PAIR_USDT_USDC), 500e6);
        bytes32[] memory liquidityConfig_init = new bytes32[](1);
        liquidityConfig_init[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, PAIR_USDT_USDC.getActiveId());
        PAIR_USDT_USDC.mint(address(this), liquidityConfig_init, address(this));
        uint256[] memory ids_init = new uint256[](1);
        ids_init[0] = PAIR_USDT_USDC.getActiveId();
        uint256[] memory amounts_init = new uint256[](1);
        PAIR_USDT_USDC.approveForAll(address(JOE_LENDING), true);
        amounts_init[0] = PAIR_USDT_USDC.balanceOf(address(this), PAIR_USDT_USDC.getActiveId());
        JOE_LENDING.deposit(ids_init, amounts_init);
        amounts_init[0] = JOE_LENDING.getUserBorrowableAmount(address(this), ids_init[0]);
        JOE_LENDING.borrow(ids_init, amounts_init);

        // Fund the player
        USDT.transfer(PLAYER, 1000e6);
        USDC.transfer(PLAYER, 1000e6);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function isSolved() external view returns (bool) {
        return USDJ.balanceOf(PLAYER) > 1900e18;
    }
}
