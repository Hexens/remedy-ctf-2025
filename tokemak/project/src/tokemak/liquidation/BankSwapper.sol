// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IAsyncSwapper, SwapParams } from "src/tokemak/interfaces/liquidation/IAsyncSwapper.sol";
import { SystemComponent, ISystemRegistry } from "src/tokemak/SystemComponent.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

/// @title Swaps tokens on Tokemak controlled "bank" multisig to avoid high slippage swaps on illiquid markets
/// @dev WARNING!! Do NOT use this contract with a non Tokemak controlled contract.  This contract forgoes some
/// necessary checks for interacting with external contracts
/// @dev In addition to the above, this should only be used via the LiquidationRow.sol contract.  This contract performs
/// necessary checks to ensure the execution we are getting is within some margin
contract BankSwapper is IAsyncSwapper, SystemComponent {
    using SafeERC20 for IERC20;

    /// @notice Address of the bank contract
    address public immutable BANK;

    // @notice Reverts when the calculated buy amount is 0
    error BuyAmountZero();

    // address(this) will be LiquidationRow contract in delegatecall context
    modifier onlyLiquidator() {
        if (!systemRegistry.accessController().hasRole(Roles.BANK_SWAP_MANAGER, address(this))) {
            revert Errors.AccessDenied();
        }
        _;
    }

    constructor(address _bank, ISystemRegistry _systemRegistry) SystemComponent(_systemRegistry) {
        Errors.verifyNotZero(_bank, "_bank");
        Errors.verifyNotZero(address(_systemRegistry.rootPriceOracle()), "_systemRegistry.rootPriceOracle");

        // slither-disable-next-line missing-zero-check
        BANK = _bank;
    }

    /// @inheritdoc IAsyncSwapper
    function swap(
        SwapParams memory swapParams
    ) external onlyLiquidator returns (uint256 buyTokenAmountReceived) {
        IERC20 sellToken = IERC20(swapParams.sellTokenAddress);
        IERC20 buyToken = IERC20(swapParams.buyTokenAddress);
        uint256 sellAmount = swapParams.sellAmount;

        IRootPriceOracle oracle = systemRegistry.rootPriceOracle();
        uint256 sellTokenPrice = oracle.getPriceInEth(swapParams.sellTokenAddress);
        uint256 buyTokenPrice = oracle.getPriceInEth(swapParams.buyTokenAddress);

        // Expected buy amount from Price Oracle
        buyTokenAmountReceived = (sellAmount * sellTokenPrice) / buyTokenPrice;

        if (buyTokenAmountReceived == 0) {
            revert BuyAmountZero();
        }

        sellToken.safeTransfer(BANK, sellAmount);
        // slither-disable-next-line arbitrary-send-erc20
        buyToken.safeTransferFrom(BANK, address(this), buyTokenAmountReceived);

        // slither-disable-next-line reentrancy-events
        emit Swapped(address(sellToken), address(buyToken), sellAmount, buyTokenAmountReceived, buyTokenAmountReceived);
    }
}
