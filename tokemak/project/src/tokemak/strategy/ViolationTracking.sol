// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

library ViolationTracking {
    uint16 internal constant TAIL_MASK = 1 << 9;
    uint16 internal constant HEAD_MASK = 1;

    struct State {
        uint8 violationCount;
        uint8 len;
        uint16 violations;
    }

    function insert(State storage self, bool isViolation) internal {
        bool tailValue = (self.violations & TAIL_MASK) > 0;

        // push new spot into the queue (default false)
        self.violations <<= 1;

        // flip the bit to true and increment counter if it is a violation
        if (isViolation) {
            self.violations |= HEAD_MASK;
            self.violationCount += 1;
        }

        // if we're dropping a violation then decrement the counter
        if (tailValue) {
            self.violationCount -= 1;
        }

        if (self.len < 10) {
            self.len += 1;
        }
    }

    function reset(
        State storage self
    ) internal {
        self.violationCount = 0;
        self.violations = 0;
        self.len = 0;
    }
}
