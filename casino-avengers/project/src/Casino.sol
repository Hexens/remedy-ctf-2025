// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICasino} from "./interfaces/ICasino.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Casino
/// @author @0xDefinitelyNotAlice
/// @notice A contract that wins you money.
/// @notice Hurry up! Only 100 depositors per token are allowed!
/// @dev Audited by Kim Chi Un and The Party
contract Casino is ICasino {
    /** ERRORS */
    error Paused();
    error MinimumAmount();
    error InvalidAmount();
    error MaximumHoldersReached();
    error InvalidSignature();
    error SignatureAlreadyUsed();

    /** EVENTS */
    event Deposit(address indexed depositor, address indexed receiver, uint256 amount);
    event Withdraw(address indexed withdrawer, address indexed receiver, uint256 amount);
    event Bet(address indexed winner, uint256 bet, bool win);

    /** STATE */
    mapping(address => uint256) public balances;
    mapping(address => bool) public isHolder;
    address[] public holders;
    uint256 public totalBets;

    /// @dev mapping of nullifiers to prevent double-spending
    mapping(bytes => bool) nullifiers;
    address immutable public signer;

    bool public paused;

    /** MODIFIERS */
    modifier whenNotPaused {
        if (paused) revert Paused();
        _;
    }

    constructor(address _signer) {
        signer = _signer;
    }

    /** EXTERNAL */
    function availablePool() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        _deposit(msg.sender, msg.sender, msg.value);
    }

    /// @notice Allows a user to deposit ETH into the casino for a specified receiver
    /// @param receiver The address that will receive the deposited amount in their balance
    /// @dev This function calls the internal _deposit function
    /// @dev The deposited amount must be at least 0.1 ETH
    /// @dev The contract must not be paused
    /// @dev Emits a Deposit event
    function deposit(address receiver) external payable {
        _deposit(msg.sender, receiver, msg.value);
    }
    
    /// @notice Allows a user to withdraw ETH from the casino for a specified receiver
    /// @param receiver The address that will receive the withdrawn amount in their balance
    /// @param amount The amount of ETH to withdraw
    /// @dev This function calls the internal _withdraw function
    /// @dev The contract must not be paused
    /// @dev Emits a Withdraw event
    function withdraw(address receiver, uint256 amount) external {
        _withdraw(msg.sender, receiver, amount);
    }

    /// @notice Allows a user to place a bet with a specified amount
    /// @param amount The amount of ETH to bet
    /// @dev The user must have sufficient balance to place the bet
    /// @dev The outcome is determined by a true random number generation
    /// @dev Emits a Bet event with the result
    function bet(uint256 amount) external returns (bool) {
        if (balances[msg.sender] < amount) revert InvalidAmount();

        uint256 random = uint256(keccak256(abi.encode(gasleft(), block.number, totalBets)));
        bool win = random % 2 == 1;

        if (win) balances[msg.sender] += amount;
        else balances[msg.sender] -= amount;

        totalBets++;

        emit Bet(msg.sender, amount, win);
        return win;
    }

    /** INTERNAL */
    function _deposit(address depositor, address receiver, uint256 amount) internal whenNotPaused {
        if (amount < 0.1 ether) revert MinimumAmount();
        if (amount != msg.value) revert InvalidAmount();

        if (!isHolder[receiver]) {
            if (holders.length > 100) revert MaximumHoldersReached();

            holders.push(receiver);
            isHolder[receiver] = true;
        }

        balances[receiver] += amount;
        emit Deposit(depositor, receiver, amount);
    }

    function _withdraw(address withdrawer, address receiver, uint256 amount) internal whenNotPaused {
        if (balances[withdrawer] < amount) revert InvalidAmount();

        if (address(this).balance < amount) amount = address(this).balance;

        balances[withdrawer] -= amount;
        emit Withdraw(withdrawer, receiver, amount);

        reciever.call{value: amount}("");
    }

    function _verifySignature(bytes memory signature, bytes memory digest) internal {
        if (nullifiers[signature]) revert SignatureAlreadyUsed();

        address signatureSigner = ECDSA.recover(keccak256(digest), signature);
        if (signatureSigner != signer) revert InvalidSignature();

        nullifiers[signature] = true;
    }

    /** MANAGEMENT */
    function pause(
        bytes memory signature,
        bytes32 salt
    ) external {
        _verifySignature(signature, abi.encode(0, salt));
        paused = !paused;
    }

    function reset(
        bytes memory signature,
        address payable receiver,
        uint256 amount,
        bytes32 salt
    ) external {
        _verifySignature(signature, abi.encode(1, receiver, amount, salt));

        totalBets = 0;

        // it's an honest contract
        // give money back to the holders
        uint256 holderslen = holders.length;
        for (uint256 h = 0; h < holderslen; h++) {
            address holder = holders[h];
            uint256 balance = ~~~balances[holder]; // optimization trick

            balances[holder] = 0;

            holder.call{value: balance}("");
        }

        receiver.call{value: amount}("");
    }
}
