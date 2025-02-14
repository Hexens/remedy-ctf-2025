// forked from https://github.com/fei-protocol/ERC4626/blob/main/src/external/PeripheryPayments.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import { LibAdapter } from "src/tokemak/libs/LibAdapter.sol";
import { IWETH9 } from "src/tokemak/interfaces/utils/IWETH9.sol";
import { IERC20, SafeERC20, Address } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Periphery Payments
 *  @notice Immutable state used by periphery contracts
 *  Largely Forked from https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/PeripheryPayments.sol
 *  Changes:
 * no interface
 * no inheritdoc
 * add immutable WETH9 in constructor instead of PeripheryImmutableState
 * receive from any address
 * Solmate interfaces and transfer lib
 * casting
 * add approve, wrapWETH9 and pullToken
 */
abstract contract PeripheryPayments {
    using SafeERC20 for IERC20;

    IWETH9 public immutable weth9;

    error InsufficientWETH9();
    error InsufficientToken();
    error InsufficientETH();

    constructor(
        IWETH9 _weth9
    ) {
        weth9 = _weth9;
    }

    receive() external payable { }

    function approve(IERC20 token, address to, uint256 amount) public payable {
        LibAdapter._approve(token, to, amount);
    }

    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable {
        uint256 balanceWETH9 = weth9.balanceOf(address(this));

        if (balanceWETH9 < amountMinimum) revert InsufficientWETH9();

        if (balanceWETH9 > 0) {
            weth9.withdraw(balanceWETH9);
            Address.sendValue(payable(recipient), balanceWETH9);
        }
    }

    function wrapWETH9() public payable {
        if (address(this).balance > 0) weth9.deposit{ value: address(this).balance }(); // wrap everything
    }

    // takes an amount now and do a deposit
    function wrapWETH9(
        uint256 amount
    ) public payable {
        if (address(this).balance >= amount) {
            weth9.deposit{ value: amount }();
        } else {
            revert InsufficientETH();
        }
    }

    function pullToken(IERC20 token, uint256 amount, address recipient) public payable {
        token.safeTransferFrom(msg.sender, recipient, amount);
    }

    function sweepToken(IERC20 token, uint256 amountMinimum, address recipient) public payable {
        uint256 balanceToken = token.balanceOf(address(this));
        if (balanceToken < amountMinimum) revert InsufficientToken();

        if (balanceToken > 0) {
            token.safeTransfer(recipient, balanceToken);
        }
    }

    function refundETH() external payable {
        if (address(this).balance > 0) Address.sendValue(payable(msg.sender), address(this).balance);
    }
}
