// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IDestinationAdapter } from "src/tokemak/interfaces/destinations/IDestinationAdapter.sol";

/**
 * @title IPoolAdapter
 * @dev This is an interface to mark adapters as ones that are dedicated for liquidity deployment/withdrawal
 *      to/from pools of a different protocols and to be registered in Destination Registry.
 *      It shares unified functions to implement with basic params and `extraParams`
 *      which can contain protocol or pool-specific params.
 */
interface IPoolAdapter is IDestinationAdapter {
    /**
     * @notice Deploy liquidity to the associated destination
     * @dev Calls into external contract
     * @param amounts Amounts of corresponding tokens to deploy
     * @param minLpMintAmount Min amount of LP tokens to mint in the deployment
     * @param extraParams Encoded params that are specific to the given destination
     */
    function addLiquidity(uint256[] calldata amounts, uint256 minLpMintAmount, bytes calldata extraParams) external;

    /**
     * @notice Withdraw liquidity from the associated destination
     * @dev Calls into external contract
     * @param amounts Amounts of corresponding tokens to withdraw
     * @param maxLpBurnAmount Max amount of LP tokens to burn in the withdrawal
     * @param extraParams Encoded params that are specific to the given destination
     * @return actualAmounts Amounts of tokens that were actually withdrawn
     */
    function removeLiquidity(
        uint256[] calldata amounts,
        uint256 maxLpBurnAmount,
        bytes calldata extraParams
    ) external returns (uint256[] memory actualAmounts);
}
