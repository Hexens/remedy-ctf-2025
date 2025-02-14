// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import { IERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

/// @notice ERC20 token functionality converted into a library. Based on OZ's v5
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC20/ERC20.sol
library AutopoolToken {
    struct TokenData {
        /// @notice Token balances
        /// @dev account => balance
        mapping(address => uint256) balances;
        /// @notice Account spender allowances
        /// @dev account => spender => allowance
        mapping(address => mapping(address => uint256)) allowances;
        /// @notice Total supply of the pool. Be careful when using this directly from the struct. The pool itself
        /// modifies this number based on unlocked profited shares
        uint256 totalSupply;
        /// @notice ERC20 Permit nonces
        /// @dev account -> nonce. Exposed via `nonces(owner)`
        mapping(address => uint256) nonces;
    }

    /// @notice EIP2612 permit type hash
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice EIP712 domain type hash
    bytes32 public constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
    /// @param sender Address whose tokens are being transferred.
    /// @param balance Current balance for the interacting account.
    /// @param needed Minimum amount required to perform a transfer.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @dev Indicates a failure with the token `sender`. Used in transfers.
    /// @param sender Address whose tokens are being transferred.
    error ERC20InvalidSender(address sender);

    /// @dev Indicates a failure with the token `receiver`. Used in transfers.
    /// @param receiver Address to which tokens are being transferred.
    error ERC20InvalidReceiver(address receiver);

    /// @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
    ///@param spender Address that may be allowed to operate on tokens without being their owner.
    /// @param allowance Amount of tokens a `spender` is allowed to operate with.
    ///@param needed Minimum amount required to perform a transfer.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
    /// @param approver Address initiating an approval operation.
    error ERC20InvalidApprover(address approver);

    /// @dev Indicates a failure with the `spender` to be approved. Used in approvals.
    /// @param spender Address that may be allowed to operate on tokens without being their owner.
    error ERC20InvalidSpender(address spender);

    /// @dev Permit deadline has expired.
    error ERC2612ExpiredSignature(uint256 deadline);
    /// @dev Mismatched signature.
    error ERC2612InvalidSigner(address signer, address owner);
    /// @dev The nonce used for an `account` is not the expected current nonce.
    error InvalidAccountNonce(address account, uint256 currentNonce);

    /// @dev Emitted when `value` tokens are moved from one account `from` to another `to`.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev Emitted when the allowance of a `spender` for an `owner` is set by a call to {approve}.
    /// `value` is the new allowance.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev Sets a `value` amount of tokens as the allowance of `spender` over the caller's tokens.
    function approve(TokenData storage data, address spender, uint256 value) external returns (bool) {
        address owner = msg.sender;
        approve(data, owner, spender, value);
        return true;
    }

    /// @dev Sets `value` as the allowance of `spender` over the `owner` s tokens.
    function approve(TokenData storage data, address owner, address spender, uint256 value) public {
        _approve(data, owner, spender, value, true);
    }

    function transfer(TokenData storage data, address to, uint256 value) external returns (bool) {
        address owner = msg.sender;
        _transfer(data, owner, to, value);
        return true;
    }

    /// @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism.
    /// value` is then deducted from the caller's allowance.
    function transferFrom(TokenData storage data, address from, address to, uint256 value) external returns (bool) {
        address spender = msg.sender;
        _spendAllowance(data, from, spender, value);
        _transfer(data, from, to, value);
        return true;
    }

    /// @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
    function mint(TokenData storage data, address account, uint256 value) external {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(data, address(0), account, value);
    }

    /// @dev Destroys a `value` amount of tokens from `account`, lowering the total supply.
    function burn(TokenData storage data, address account, uint256 value) external {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(data, account, address(0), value);
    }

    function permit(
        TokenData storage data,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        uint256 nonce;
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here. Nonces starts at 0
            nonce = data.nonces[owner]++;
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));

        bytes32 hash = ECDSA.toTypedDataHash(IERC20Permit(address(this)).DOMAIN_SEPARATOR(), structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }

        approve(data, owner, spender, value);
    }

    /// @dev Moves a `value` amount of tokens from `from` to `to`.
    function _transfer(TokenData storage data, address from, address to, uint256 value) private {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(data, from, to, value);
    }

    /// @dev Updates `owner` s allowance for `spender` based on spent `value`.
    function _spendAllowance(TokenData storage data, address owner, address spender, uint256 value) private {
        uint256 currentAllowance = data.allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(data, owner, spender, currentAllowance - value, false);
            }
        }
    }

    /// @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
    /// (or `to`) is the zero address.
    function _update(TokenData storage data, address from, address to, uint256 value) private {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            data.totalSupply += value;
        } else {
            uint256 fromBalance = data.balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                data.balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                data.totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                data.balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /// @dev Variant of `_approve` with an optional flag to enable or disable the Approval event.
    function _approve(TokenData storage data, address owner, address spender, uint256 value, bool emitEvent) private {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        data.allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }
}
