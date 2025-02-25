// forked from https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/ISelfPermit.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title Self Permit
/// @notice Functionality to call permit on any EIP-2612-compliant token for use in the route
interface ISelfPermit {
    /// @notice Permit call failed and allowance is not sufficient compared to the desired value
    error PermitFailed();

    /**
     * @notice Permits this contract to spend a given token from `msg.sender`
     * @dev The `owner` is always msg.sender and the `spender` is always address(this).
     * @param token The address of the token spent
     * @param value The amount that can be spent of token
     * @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
     * @param v Must produce valid secp256k1 signature from the holder along with `r` and `s`
     * @param r Must produce valid secp256k1 signature from the holder along with `v` and `s`
     * @param s Must produce valid secp256k1 signature from the holder along with `r` and `v`
     */
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
}
