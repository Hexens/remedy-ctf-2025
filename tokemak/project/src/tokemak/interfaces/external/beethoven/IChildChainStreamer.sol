// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// solhint-disable func-name-mixedcase
// slither-disable-start naming-convention

/**
 * @title Child-Chain Streamer
 * @author Curve.Fi
 * @notice Evenly streams one or more reward tokens to a single recipient
 */
interface IChildChainStreamer {
    /// @notice The count of reward tokens
    function reward_count() external view returns (uint256);

    /// @notice The address of the reward token at a given index
    function reward_tokens(
        uint256 index
    ) external view returns (IERC20);
}
// slither-disable-end naming-convention
