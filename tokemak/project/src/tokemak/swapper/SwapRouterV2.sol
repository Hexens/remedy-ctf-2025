// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "src/tokemak/interfaces/swapper/ISwapRouter.sol";
import { ISwapRouterV2 } from "src/tokemak/interfaces/swapper/ISwapRouterV2.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { SwapRouter } from "src/tokemak/swapper/SwapRouter.sol";
import { TransientStorage } from "src/tokemak/libs/TransientStorage.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";

contract SwapRouterV2 is ISwapRouterV2, SwapRouter {
    using SafeERC20 for IERC20;

    uint256 private constant _NUM_ROUTES = uint256(keccak256(bytes("_NUM_ROUTES"))) - 1;
    uint256 private constant _CURRENT_SWAP_INDEX = uint256(keccak256(bytes("CURRENT_SWAP_INDEX"))) - 1;

    constructor(
        ISystemRegistry _systemRegistry
    ) SwapRouter(_systemRegistry) { }

    /// @inheritdoc ISwapRouter
    function swapForQuote(
        address assetToken,
        uint256 sellAmount,
        address quoteToken,
        uint256 minBuyAmount
    ) public override(SwapRouter, ISwapRouter) onlyDestinationVault(msg.sender) nonReentrant returns (uint256) {
        if (!_transientRoutesAvailable()) {
            return _swapForQuote(assetToken, sellAmount, quoteToken, minBuyAmount);
        }
        // if no transient -> use swapRoutes
        // if transient + empty route -> use swapRoutes
        // if transient + non-empty route -> use transient
        // if transient + index out of bounds -> revert

        // maintain txn index
        uint256 index = _getCurrentSwapIndex();
        _setCurrentSwapIndex(index + 1);

        if (index >= _getNumSwapRoutes()) revert Errors.InvalidParams();

        ISwapRouterV2.UserSwapData memory route = _getTransientRoutes(index);
        if (route.target == address(0)) {
            return _swapForQuote(assetToken, sellAmount, quoteToken, minBuyAmount);
        } else {
            _validateSwapParams(assetToken, sellAmount, quoteToken);
            return _swapForQuoteUserRoute(assetToken, sellAmount, quoteToken, minBuyAmount, route);
        }
    }

    function _swapForQuoteUserRoute(
        address assetToken,
        uint256 sellAmount,
        address quoteToken,
        uint256 minBuyAmount,
        ISwapRouterV2.UserSwapData memory transientRoute
    ) internal returns (uint256) {
        if (transientRoute.fromToken != assetToken || transientRoute.toToken != quoteToken) {
            revert Errors.InvalidConfiguration();
        }

        uint256 balanceDiff = IERC20(quoteToken).balanceOf(address(this));
        IERC20(assetToken).safeTransferFrom(msg.sender, transientRoute.target, sellAmount);

        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = transientRoute.target.call(transientRoute.data);
        // slither-disable-end low-level-calls
        if (!success) revert SwapFailed();

        balanceDiff = IERC20(quoteToken).balanceOf(address(this)) - balanceDiff;
        if (balanceDiff < minBuyAmount) revert Errors.SlippageExceeded(minBuyAmount, balanceDiff);

        IERC20(quoteToken).safeTransfer(msg.sender, balanceDiff);
        emit SwapForQuoteSuccessful(assetToken, sellAmount, quoteToken, minBuyAmount, balanceDiff);
        return balanceDiff;
    }

    function _validateSwapParams(address assetToken, uint256 sellAmount, address quoteToken) internal pure {
        if (sellAmount == 0) revert Errors.ZeroAmount();
        if (assetToken == quoteToken) revert Errors.InvalidParams();
        Errors.verifyNotZero(assetToken, "assetToken");
        Errors.verifyNotZero(quoteToken, "quoteToken");
    }

    function initTransientSwap(
        ISwapRouterV2.UserSwapData[] memory customRoutes
    ) public onlyAutoPilotRouter {
        if (_transientRoutesAvailable()) revert Errors.AccessDenied();
        TransientStorage.setBytes(abi.encode(0), _CURRENT_SWAP_INDEX);

        uint256 numRoutes = customRoutes.length;
        TransientStorage.setBytes(abi.encode(numRoutes), _NUM_ROUTES);
        for (uint256 i = 0; i < numRoutes;) {
            TransientStorage.setBytes(abi.encode(customRoutes[i]), _computeTransientRouteIndex(i));
            unchecked {
                ++i;
            }
        }
    }

    function exitTransientSwap() public onlyAutoPilotRouter {
        uint256 numRoutes = _getNumSwapRoutes();
        for (uint256 i = 0; i < numRoutes;) {
            TransientStorage.clearBytes(_computeTransientRouteIndex(i));
            unchecked {
                ++i;
            }
        }
        TransientStorage.clearBytes(_NUM_ROUTES);
        TransientStorage.clearBytes(_CURRENT_SWAP_INDEX);
    }

    function _setCurrentSwapIndex(
        uint256 index
    ) internal {
        TransientStorage.setBytes(abi.encode(index), _CURRENT_SWAP_INDEX);
    }

    function _getCurrentSwapIndex() internal view returns (uint256) {
        bytes memory indexEncoded = TransientStorage.getBytes(_CURRENT_SWAP_INDEX);
        return abi.decode(indexEncoded, (uint256));
    }

    function _getNumSwapRoutes() internal view returns (uint256) {
        bytes memory numRoutesEncoded = TransientStorage.getBytes(_NUM_ROUTES);
        return abi.decode(numRoutesEncoded, (uint256));
    }

    function _getTransientRoutes(
        uint256 index
    ) internal view returns (UserSwapData memory customRoute) {
        uint256 routeSlot = _computeTransientRouteIndex(index);
        bytes memory customRouteEncoded = TransientStorage.getBytes(routeSlot);
        customRoute = abi.decode(customRouteEncoded, (UserSwapData));
    }

    function _transientRoutesAvailable() internal view returns (bool) {
        return TransientStorage.dataExists(_NUM_ROUTES);
    }

    function _computeTransientRouteIndex(
        uint256 index
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(_NUM_ROUTES, index)));
    }

    modifier onlyAutoPilotRouter() {
        if (msg.sender != address(systemRegistry.autoPoolRouter())) revert Errors.AccessDenied();
        _;
    }
}
