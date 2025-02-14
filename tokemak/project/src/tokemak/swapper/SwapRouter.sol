// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import { Errors } from "src/tokemak/utils/Errors.sol";
import { ISyncSwapper } from "src/tokemak/interfaces/swapper/ISyncSwapper.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IDestinationVaultRegistry } from "src/tokemak/interfaces/vault/IDestinationVaultRegistry.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

contract SwapRouter is SystemComponent, ISwapRouter, SecurityBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // 5/16/2023: open issue https://github.com/crytic/slither/issues/456
    // slither-disable-next-line uninitialized-state
    mapping(address => mapping(address => SwapData[])) public swapRoutes;

    modifier onlyDestinationVault(
        address vaultAddress
    ) {
        IDestinationVaultRegistry destinationVaultRegistry = systemRegistry.destinationVaultRegistry();
        if (!destinationVaultRegistry.isRegistered(vaultAddress)) revert Errors.AccessDenied();
        _;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) { }

    /// @inheritdoc ISwapRouter
    function setSwapRoute(
        address assetToken,
        SwapData[] calldata _swapRoute
    ) external hasRole(Roles.SWAP_ROUTER_MANAGER) {
        Errors.verifyNotZero(assetToken, "assetToken");

        uint256 length = _swapRoute.length;
        if (length == 0) revert Errors.InvalidParams();

        address quoteToken = _swapRoute[length - 1].token;
        delete swapRoutes[assetToken][quoteToken];
        SwapData[] storage swapRoute = swapRoutes[assetToken][quoteToken];

        address fromToken = assetToken;
        for (uint256 hop = 0; hop < length; ++hop) {
            SwapData memory route = _swapRoute[hop];

            Errors.verifyNotZero(route.token, "swap token");
            Errors.verifyNotZero(route.pool, "swap pool");
            Errors.verifyNotZero(address(route.swapper), "swap swapper");

            if (address(route.swapper.router()) != address(this)) revert Errors.InvalidParams();

            route.swapper.validate(fromToken, route);

            swapRoute.push(route);
            fromToken = route.token;
        }

        emit SwapRouteSet(assetToken, _swapRoute);
    }

    receive() external payable {
        // we accept ETH so we can unwrap WETH
    }

    /// @inheritdoc ISwapRouter
    function swapForQuote(
        address assetToken,
        uint256 sellAmount,
        address quoteToken,
        uint256 minBuyAmount
    ) external virtual override onlyDestinationVault(msg.sender) nonReentrant returns (uint256) {
        return _swapForQuote(assetToken, sellAmount, quoteToken, minBuyAmount);
    }

    function _swapForQuote(
        address assetToken,
        uint256 sellAmount,
        address quoteToken,
        uint256 minBuyAmount
    ) internal returns (uint256) {
        if (sellAmount == 0) revert Errors.ZeroAmount();
        if (assetToken == quoteToken) revert Errors.InvalidParams();
        Errors.verifyNotZero(assetToken, "assetToken");
        Errors.verifyNotZero(quoteToken, "quoteToken");

        SwapData[] memory routes = swapRoutes[assetToken][quoteToken];
        uint256 length = routes.length;

        if (length == 0) revert SwapRouteLookupFailed(assetToken, quoteToken);

        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), sellAmount);
        uint256 balanceBefore = IERC20(quoteToken).balanceOf(address(this));

        // disable slither because it doesn't understand that zero check is done in the setSwapRoute function
        // slither-disable-next-line missing-zero-check
        address currentToken = assetToken;
        uint256 currentAmount = sellAmount;
        for (uint256 hop = 0; hop < length; ++hop) {
            // slither-disable-start low-level-calls
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory data) = address(routes[hop].swapper).delegatecall(
                abi.encodeCall(
                    ISyncSwapper.swap,
                    (routes[hop].pool, currentToken, currentAmount, routes[hop].token, 0, routes[hop].data)
                )
            );
            // slither-disable-end low-level-calls

            if (!success) {
                if (data.length == 0) revert SwapFailed();

                // forward the original revert error
                //slither-disable-start assembly
                //solhint-disable-next-line no-inline-assembly
                assembly {
                    revert(add(32, data), mload(data))
                }
                //slither-disable-end assembly
            }

            currentToken = routes[hop].token;
            currentAmount = abi.decode(data, (uint256));
        }
        uint256 balanceAfter = IERC20(quoteToken).balanceOf(address(this));

        uint256 balanceDiff = balanceAfter - balanceBefore;
        if (balanceDiff < minBuyAmount) revert MaxSlippageExceeded();

        IERC20(quoteToken).safeTransfer(msg.sender, balanceDiff);

        emit SwapForQuoteSuccessful(assetToken, sellAmount, quoteToken, minBuyAmount, balanceDiff);

        return balanceDiff;
    }
}
