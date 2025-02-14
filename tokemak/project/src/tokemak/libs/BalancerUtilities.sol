// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IVault } from "src/tokemak/interfaces/external/balancer/IVault.sol";
import { IBalancerPool } from "src/tokemak/interfaces/external/balancer/IBalancerPool.sol";
import { IBalancerMetaStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerMetaStablePool.sol";
import { IBalancerComposableStablePool } from "src/tokemak/interfaces/external/balancer/IBalancerComposableStablePool.sol";

library BalancerUtilities {
    /**
     * @notice Checks if a given address is Balancer Composable pool
     * @dev Using the presence of a getBptIndex() fn as an indicator of pool type
     */
    function isComposablePool(
        address pool
    ) public view returns (bool) {
        // slither-disable-start low-level-calls
        // solhint-disable-next-line no-unused-vars
        (bool success, bytes memory data) =
            pool.staticcall(abi.encodeCall(IBalancerComposableStablePool.getBptIndex, ()));
        if (success) {
            return data.length > 0;
        }
        // slither-disable-end low-level-calls
        return success;
    }

    /**
     * @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
     */
    function _convertERC20sToAddresses(
        IERC20[] memory tokens
    ) internal pure returns (address[] memory assets) {
        //slither-disable-start assembly
        //solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
        //slither-disable-end assembly
    }

    /**
     * @dev This helper function to retrieve Balancer pool tokens
     */
    function _getPoolTokens(
        IVault balancerVault,
        address balancerPool
    ) internal view returns (IERC20[] memory assets, uint256[] memory balances) {
        bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

        (assets, balances,) = balancerVault.getPoolTokens(poolId);
    }

    /// @notice This function retrieves tokens (skipping the BPT) from Balancer composable pools
    function _getComposablePoolTokensSkipBpt(
        IVault balancerVault,
        address balancerPool
    ) internal view returns (IERC20[] memory tokens, uint256[] memory balances) {
        (IERC20[] memory allTokens, uint256[] memory allBalances) =
            BalancerUtilities._getPoolTokens(balancerVault, balancerPool);

        uint256 nTokens = allTokens.length;
        tokens = new IERC20[](nTokens - 1);
        balances = new uint256[](nTokens - 1);

        uint256 lastIndex = 0;
        uint256 bptIndex = IBalancerComposableStablePool(balancerPool).getBptIndex();
        for (uint256 i = 0; i < nTokens;) {
            // skip pool token
            if (i == bptIndex) {
                unchecked {
                    ++i;
                }
                continue;
            }
            // copy tokens and balances
            tokens[lastIndex] = allTokens[i];
            balances[lastIndex] = allBalances[i];
            unchecked {
                ++i;
                ++lastIndex;
            }
        }
    }

    /**
     * @notice Gets the virtual price of a Balancer metastable pool with an invariant adjustment
     * @dev removes accrued admin fees that haven't been taken yet by Balancer
     */
    function _getMetaStableVirtualPrice(
        IVault balancerVault,
        address balancerPool
    ) internal view returns (uint256 virtualPrice) {
        IBalancerMetaStablePool pool = IBalancerMetaStablePool(balancerPool);
        virtualPrice = pool.getRate(); // e18

        uint256 totalSupply = pool.totalSupply(); // e18
        uint256 unscaledInv = (virtualPrice * totalSupply) / 1e18; // e18
        uint256 lastInvariant = pool.getLastInvariant(); // e18
        if (unscaledInv > lastInvariant) {
            uint256 delta = unscaledInv - lastInvariant; // e18 - e18 -> e18
            uint256 swapFee = balancerVault.getProtocolFeesCollector().getSwapFeePercentage(); //e18
            uint256 protocolPortion = ((delta * swapFee) / 1e18); // e18
            uint256 scaledInv = unscaledInv - protocolPortion; // e18 - e18 -> e18
            virtualPrice = scaledInv * 1e18 / totalSupply; // e36 / e18 -> e18
        }
    }
}
