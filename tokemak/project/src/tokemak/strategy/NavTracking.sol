// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

library NavTracking {
    uint8 internal constant MAX_NAV_TRACKING = 91;

    error NavHistoryInsufficient();
    error InvalidNavTimestamp(uint40 current, uint40 provided);

    event NavHistoryInsert(uint256 navPerShare, uint40 timestamp);

    struct State {
        uint8 len;
        uint8 currentIndex;
        uint40 lastFinalizedTimestamp;
        uint256[MAX_NAV_TRACKING] history;
    }

    function insert(State storage self, uint256 navPerShare, uint40 timestamp) internal {
        if (timestamp < self.lastFinalizedTimestamp) revert InvalidNavTimestamp(self.lastFinalizedTimestamp, timestamp);

        // if it's been a day since the last finalized value, then finalize the current value
        // otherwise continue to overwrite the currentIndex
        if (timestamp - self.lastFinalizedTimestamp >= 1 days) {
            if (self.lastFinalizedTimestamp > 0) {
                self.currentIndex = (self.currentIndex + 1) % MAX_NAV_TRACKING;
            }
            self.lastFinalizedTimestamp = timestamp;
        }

        self.history[self.currentIndex] = navPerShare;
        if (self.len < MAX_NAV_TRACKING) {
            self.len += 1;
        }

        emit NavHistoryInsert(navPerShare, timestamp);
    }

    // the way this information is used, it is ok for it to not perfectly be daily
    // gaps of a few days are acceptable and do not materially degrade the NAV decay checks
    function getDaysAgo(State memory self, uint8 daysAgo) internal pure returns (uint256) {
        if (daysAgo >= self.len) revert NavHistoryInsufficient();

        uint8 targetIndex = (MAX_NAV_TRACKING + self.currentIndex - daysAgo) % MAX_NAV_TRACKING;
        return self.history[targetIndex];
    }
}
