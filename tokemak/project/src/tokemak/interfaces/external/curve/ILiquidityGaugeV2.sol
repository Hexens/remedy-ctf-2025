// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase
// slither-disable-start naming-convention
interface ILiquidityGaugeV2 {
    /// @notice the address of the reward contract
    function reward_contract() external view returns (address);

    /// @notice get the reward token address
    function reward_tokens(
        uint256 i
    ) external view returns (address);

    /// @notice claim available reward tokens for `_account`
    function claim_rewards(
        address _account
    ) external;

    /// @notice deposit `_value` LP tokens to the gauge
    function deposit(uint256 _value, address _addr) external;
}
// slither-disable-end naming-convention
