// forked from https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/SelfPermit.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

import { ISelfPermit } from "src/tokemak/interfaces/utils/ISelfPermit.sol";

/// @title Self Permit
/// @notice Functionality to call permit on any EIP-2612-compliant token for use in the route
/// @dev These functions are expected to be embedded in multicalls to allow EOAs to approve a
///      contract and call a function that requires an approval in a single transaction.
///      It implements a "trustless" permit scheme where the contract will attempt to call
///      permit() first and if it fails, it will check the allowance and revert if it's insufficient.
///      This is to prevent frontrunning attacks where the allowance is set to 0 after the permit call
///      by the third party. Ref: https://www.trust-security.xyz/post/permission-denied
abstract contract SelfPermit is ISelfPermit {
    /// @inheritdoc ISelfPermit
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable override {
        // Run permit() without allowance check to advance nonce if possible
        try IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s) {
            return;
        } catch {
            // Permit potentially got frontrun. Continue anyways if allowance is sufficient
            if (IERC20(token).allowance(msg.sender, address(this)) >= value) {
                return;
            }
        }
        revert PermitFailed();
    }
}
