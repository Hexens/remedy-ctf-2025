// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { Stats } from "src/tokemak/stats/Stats.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { MessageTypes } from "src/tokemak/libs/MessageTypes.sol";

abstract contract LSTCalculatorBase is ILSTStats, BaseStatsCalculator {
    /// @notice time in seconds between apr snapshots
    uint256 public constant APR_SNAPSHOT_INTERVAL_IN_SEC = 3 * 24 * 60 * 60; // 3 days

    /// @notice time in seconds for the initialization period
    uint256 public constant APR_FILTER_INIT_INTERVAL_IN_SEC = 9 * 24 * 60 * 60; // 9 days

    /// @notice time in seconds between discount snapshots
    uint256 public constant DISCOUNT_SNAPSHOT_INTERVAL_IN_SEC = 24 * 60 * 60; // 1 day

    /// @notice alpha for filter
    uint256 public constant ALPHA = 1e17; // 0.1; must be 0 < x <= 1e18

    /// @notice lstTokenAddress is the address for the LST that the stats are for
    address public lstTokenAddress;

    /// @notice ethPerToken at the last snapshot for base apr
    uint256 public lastBaseAprEthPerToken;

    /// @notice timestamp of the last snapshot for base apr
    uint256 public lastBaseAprSnapshotTimestamp;

    /// @notice timestamp of the last discount snapshot
    uint256 public lastDiscountSnapshotTimestamp;

    /// @notice filtered base apr
    uint256 public baseApr;

    /// @notice the last 10 daily discount/premium values for the token
    uint24[10] public discountHistory;

    /// @notice timestamp that the token reached 1 pct discount
    uint40 public discountTimestampByPercent;

    // TODO: verify that we save space by using a uint8. It should be packed with the bool & bytes32 below
    /// @dev the next index in the discountHistory buffer to be written
    uint8 private discountHistoryIndex;

    /// @notice indicates if baseApr filter is initialized
    bool public baseAprFilterInitialized;

    // slither-disable-start constable-states
    /// @notice Whether to send message to destination chain on _snapshot
    bool public destinationMessageSend = false;
    // slither-disable-end constable-states

    bytes32 internal _aprId;

    struct InitData {
        address lstTokenAddress;
    }

    event BaseAprSnapshotTaken(
        uint256 priorEthPerToken,
        uint256 priorTimestamp,
        uint256 currentEthPerToken,
        uint256 currentTimestamp,
        uint256 priorBaseApr,
        uint256 currentBaseApr
    );

    event DiscountSnapshotTaken(uint256 priorTimestamp, uint24 discount, uint256 currentTimestamp);

    event DestinationMessageSendSet(bool destinationMessageSend);

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseStatsCalculator(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes memory initData) public virtual override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));
        lstTokenAddress = decodedInitData.lstTokenAddress;
        _aprId = Stats.generateRawTokenIdentifier(lstTokenAddress);

        uint256 currentEthPerToken = calculateEthPerToken();
        lastBaseAprEthPerToken = currentEthPerToken;
        lastBaseAprSnapshotTimestamp = block.timestamp;
        baseAprFilterInitialized = false;

        // slither-disable-next-line reentrancy-benign
        updateDiscountHistory(currentEthPerToken);
        updateDiscountTimestampByPercent();
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return lstTokenAddress;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    function _snapshot() internal virtual override {
        uint256 currentEthPerToken = calculateEthPerToken();
        if (_timeForAprSnapshot()) {
            uint256 currentApr = Stats.calculateAnnualizedChangeMinZero(
                lastBaseAprSnapshotTimestamp, lastBaseAprEthPerToken, block.timestamp, currentEthPerToken
            );
            uint256 newBaseApr;
            if (baseAprFilterInitialized) {
                newBaseApr = Stats.getFilteredValue(ALPHA, baseApr, currentApr);
            } else {
                // Speed up the baseApr filter ramp
                newBaseApr = currentApr;
                baseAprFilterInitialized = true;
            }

            emit BaseAprSnapshotTaken(
                lastBaseAprEthPerToken,
                lastBaseAprSnapshotTimestamp,
                currentEthPerToken,
                block.timestamp,
                baseApr,
                newBaseApr
            );

            // Send data to other chain if necessary.
            if (destinationMessageSend) {
                bytes memory message = abi.encode(
                    MessageTypes.LSTDestinationInfo({
                        snapshotTimestamp: block.timestamp,
                        newBaseApr: newBaseApr,
                        currentEthPerToken: currentEthPerToken
                    })
                );

                // slither-disable-start reentrancy-no-eth
                systemRegistry.messageProxy().sendMessage(MessageTypes.LST_SNAPSHOT_MESSAGE_TYPE, message);
                // slither-disable-end reentrancy-no-eth
            }

            baseApr = newBaseApr;
            lastBaseAprEthPerToken = currentEthPerToken;
            lastBaseAprSnapshotTimestamp = block.timestamp;
        }

        if (_timeForDiscountSnapshot()) {
            // slither-disable-next-line reentrancy-benign,reentrancy-events
            updateDiscountHistory(currentEthPerToken);
            updateDiscountTimestampByPercent();
        }
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view virtual override returns (bool) {
        // slither-disable-start timestamp
        return _timeForAprSnapshot() || _timeForDiscountSnapshot();
        // slither-disable-end timestamp
    }

    function _timeForAprSnapshot() internal view virtual returns (bool) {
        if (baseAprFilterInitialized) {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastBaseAprSnapshotTimestamp + APR_SNAPSHOT_INTERVAL_IN_SEC;
        } else {
            // slither-disable-next-line timestamp
            return block.timestamp >= lastBaseAprSnapshotTimestamp + APR_FILTER_INIT_INTERVAL_IN_SEC;
        }
    }

    function _timeForDiscountSnapshot() internal view returns (bool) {
        // slither-disable-next-line timestamp
        return block.timestamp >= lastDiscountSnapshotTimestamp + DISCOUNT_SNAPSHOT_INTERVAL_IN_SEC;
    }

    /// @inheritdoc ILSTStats
    function current() external returns (LSTStatsData memory) {
        // return the most recent snapshot timestamp
        // slither-disable-next-line timestamp
        uint256 lastSnapshotTimestamp = Math.max(lastBaseAprSnapshotTimestamp, lastDiscountSnapshotTimestamp);

        return LSTStatsData({
            lastSnapshotTimestamp: lastSnapshotTimestamp,
            baseApr: baseApr,
            discount: calculateDiscount(calculateEthPerToken()),
            discountHistory: discountHistory,
            discountTimestampByPercent: discountTimestampByPercent
        });
    }

    function calculateDiscount(
        uint256 backing
    ) private returns (int256) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();

        // slither-disable-next-line reentrancy-benign
        uint256 price = pricer.getPriceInEth(lstTokenAddress);

        // result is 1e18
        uint256 priceToBacking;
        if (usePriceAsDiscount()) {
            priceToBacking = price;
        } else {
            // price is always 1e18 and backing is in eth, which is 1e18
            priceToBacking = price * 1e18 / backing;
        }

        // positive value is a discount; negative value is a premium
        return 1e18 - int256(priceToBacking);
    }

    function updateDiscountTimestampByPercent() internal {
        uint256 discountHistoryLength = discountHistory.length;
        uint40 previousDiscount =
            discountHistory[(discountHistoryIndex + discountHistoryLength - 2) % discountHistoryLength];
        uint40 currentDiscount =
            discountHistory[(discountHistoryIndex + discountHistoryLength - 1) % discountHistoryLength];

        // ask:
        // "was this not in violation last round and now in violation this round?"
        // if yes, overwrite that slot in discountTimestampByPercent with the current timestamp
        // if no, do nothing
        // 1e5 in discountHistory means a 1% LST discount.
        // clear recorded timestamp if discount collapses to below 1%
        uint40 discountPercent = 1e5;
        bool inViolationLastSnapshot = discountPercent <= previousDiscount;
        bool inViolationThisSnapshot = discountPercent <= currentDiscount;
        if (inViolationThisSnapshot && !inViolationLastSnapshot) {
            discountTimestampByPercent = uint40(block.timestamp);
        }

        if (!inViolationThisSnapshot && inViolationLastSnapshot) {
            discountTimestampByPercent = uint40(0);
        }
    }

    function updateDiscountHistory(
        uint256 backing
    ) internal {
        // reduce precision from 18 to 7 to reduce costs
        int256 discount = calculateDiscount(backing) / 1e11;
        uint24 trackedDiscount;
        if (discount <= 0) {
            trackedDiscount = 0;
        } else if (discount >= 1e7) {
            trackedDiscount = 1e7;
        } else {
            trackedDiscount = uint24(uint256(discount));
        }

        discountHistory[discountHistoryIndex] = trackedDiscount;
        discountHistoryIndex = (discountHistoryIndex + 1) % uint8(discountHistory.length);
        // Log event for discount snapshot
        // slither-disable-next-line reentrancy-events
        emit DiscountSnapshotTaken(lastDiscountSnapshotTimestamp, trackedDiscount, block.timestamp);
        lastDiscountSnapshotTimestamp = block.timestamp;
    }

    /// @notice Switches flag for sending messages to other chains.
    function setDestinationMessageSend() external virtual hasRole(Roles.STATS_GENERAL_MANAGER) {
        Errors.verifyNotZero(address(systemRegistry.messageProxy()), "messageProxy");

        destinationMessageSend = !destinationMessageSend;
        emit DestinationMessageSendSet(destinationMessageSend);
    }

    /// @inheritdoc ILSTStats
    function calculateEthPerToken() public view virtual returns (uint256);

    /// @inheritdoc ILSTStats
    function usePriceAsDiscount() public view virtual returns (bool);
}
