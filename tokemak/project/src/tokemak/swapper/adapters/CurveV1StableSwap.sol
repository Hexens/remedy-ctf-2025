// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { ICurveV1StableSwap } from "src/tokemak/interfaces/external/curve/ICurveV1StableSwap.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";
import { BaseAdapter, ISyncSwapper } from "src/tokemak/swapper/adapters/BaseAdapter.sol";
import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";

contract CurveV1StableSwap is BaseAdapter {
    IWETH9 public immutable weth;

    constructor(address _router, address _weth) BaseAdapter(_router) {
        weth = IWETH9(_weth);
    }

    /// @inheritdoc ISyncSwapper
    function validate(address fromAddress, ISwapRouter.SwapData memory swapData) external view override {
        (int128 sellIndex, int128 buyIndex) = abi.decode(swapData.data, (int128, int128));

        ICurveV1StableSwap pool = ICurveV1StableSwap(swapData.pool);

        address sellAddress = pool.coins(_int128ToUint256(sellIndex));
        address buyAddress = pool.coins(_int128ToUint256(buyIndex));

        // verify that the fromAddress and toAddress are in the pool
        if (!isTokenMatch(fromAddress, sellAddress)) revert DataMismatch("fromAddress");
        if (!isTokenMatch(swapData.token, buyAddress)) revert DataMismatch("toAddress");
    }

    /// @inheritdoc ISyncSwapper
    function swap(
        address poolAddress,
        address sellTokenAddress,
        uint256 sellAmount,
        address buyTokenAddress,
        uint256 minBuyAmount,
        bytes memory data
    ) external override onlyRouter returns (uint256 amount) {
        (int128 sellIndex, int128 buyIndex) = abi.decode(data, (int128, int128));
        ICurveV1StableSwap pool = ICurveV1StableSwap(poolAddress);

        LibAdapter._approve(IERC20(sellTokenAddress), poolAddress, sellAmount);

        amount = pool.exchange(sellIndex, buyIndex, sellAmount, minBuyAmount);

        /**
         * The rest of the system only deals in WETH, swap if Eth.  This if statement makes sure that we cannot
         *      accidentally leave weth locked in the contract by wrapping it during the wrong operation.
         *      It also differentiates how the amount returned to swap router is calculated when swapping for
         *      Eth and swapping for weth.
         */
        if (address(this).balance > 0) {
            uint256 addressBalance = address(this).balance;
            if (buyTokenAddress == address(weth)) {
                amount += addressBalance;
            } else if (buyTokenAddress == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
                amount = addressBalance;
            } else {
                return amount;
            }
            // slither-disable-next-line arbitrary-send-eth
            weth.deposit{ value: addressBalance }();
        }
    }

    function _int128ToUint256(
        int128 value
    ) internal pure returns (uint256 result) {
        if (value < 0) {
            revert InvalidIndex();
        }
        // slither-disable-start assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            result := value
        }
        //slither-disable-end assembly
    }

    /// @notice Determine if the supplied and queried tokens match
    /// @dev Accounts of Curve 0xEeeEe... tokens and accepts WETH as its already wrapped
    /// @param fromAddress Token supplied in our config
    /// @param queriedAddress Token queried based on the supplied index
    /// @return true for "matches"
    function isTokenMatch(address fromAddress, address queriedAddress) internal view returns (bool) {
        if (queriedAddress == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER) {
            if (fromAddress == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER || fromAddress == address(weth)) {
                return true;
            }
        }

        // Only special case is the Curve 0xEeeE representation
        // All others must match exact
        return fromAddress == queriedAddress;
    }
}
