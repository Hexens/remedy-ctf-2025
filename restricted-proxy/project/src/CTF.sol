// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract CTF {

    bool public ownerWithdrawn;
    uint256 public withdrawRate;
    address public owner;
    uint256 public constant WITHDRAW_DENOMINATOR = 10000;

    constructor() payable {
        withdrawRate = 100;
        ownerWithdrawn = true;
    }

    function becomeOwner(uint256) external {
        assembly {
            sstore(owner.slot, calldataload(4))
        }
    }

    function changeWithdrawRate(uint8) external {
        assembly {
            sstore(withdrawRate.slot, calldataload(4))
        }
    }

    function withdrawFunds() external {
        assembly {
            let ownerWithdrawnSlot := sload(ownerWithdrawn.slot)
            let ownerSlot := sload(owner.slot)
            let withdrawRateSlot := sload(withdrawRate.slot)

            if iszero(ownerWithdrawnSlot) {
                revert(0, 0)
            }

            if iszero(eq(ownerSlot, caller())) {
                revert(0, 0)
            }

            sstore(ownerWithdrawn.slot, 0)

            let contractBalance := selfbalance()
            let amount := div(
                mul(contractBalance, withdrawRateSlot),
                WITHDRAW_DENOMINATOR
            )

            let success := call(gas(), caller(), amount, 0, 0, 0, 0)
            if iszero(success) {
                revert(0, 0)
            }
        }
    }
}
