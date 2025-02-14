// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { IIncentivesPricingStats } from "src/tokemak/interfaces/stats/IIncentivesPricingStats.sol";
import { Stats } from "src/tokemak/stats/Stats.sol";
import { IReward } from "src/tokemak/interfaces/external/maverick/IReward.sol";
import { IPoolPositionSlim } from "src/tokemak/interfaces/external/maverick/IPoolPositionSlim.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IRootPriceOracle } from "src/tokemak/interfaces/oracles/IRootPriceOracle.sol";
import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";

contract MaverickCalculator is BaseStatsCalculator, IDexLSTStats {
    IDexLSTStats public underlyerStats;
    IReward public boostedRewarder;
    IPoolPositionSlim public boostedPosition;
    mapping(address => uint256) public safeTotalSupplies;
    mapping(address => uint256) public lastSnapshotTimestamps;
    mapping(address => uint256) public lastSnapshotRewardPerTokens;
    mapping(address => uint256) public lastSnapshotRewardRates;

    /// @dev The Maverick pool
    address public pool;

    /// @dev Last time total APR was recorded.
    uint256 public lastSnapshotTotalAPR;

    /// @dev Last time an incentive was recorded or distributed.
    uint256 public lastIncentiveTimestamp;

    /// @dev Last time an non trivial incentive was recorded or distributed.
    uint256 public decayInitTimestamp;

    /// @dev State variable to indicate non trivial incentive APR was measured last snapshot.
    bool public decayState;

    /// @dev Incentive credits balance before decay
    uint8 public incentiveCredits;

    /// @dev Interval between two consecutive snapshot steps during the snapshot process.
    uint256 public constant SNAPSHOT_INTERVAL = 3 hours;

    /// @dev Non-trivial annual rate set at 0.5% (in fixed point format 1e18 = 1).
    uint256 public constant NON_TRIVIAL_ANNUAL_RATE = 5e15;

    /// @dev Duration after which a price/data becomes stale.
    uint40 public constant PRICE_STALE_CHECK = 12 hours;

    /// @dev Cap on allowable credits in the system.
    uint8 public constant MAX_CREDITS = 168;

    /// @dev The APR Id
    bytes32 private _aprId;

    struct InitData {
        address underlyerStats; // Maverick Dex calculator
        address boostedRewarder; // Where the Maverick Boosted Position LP tokens are staked for rewards
        address boostedPosition;
    }

    // Custom error for handling unexpected snapshot statuses
    error InvalidSnapshotStatus();
    error shouldNotResetCalculator();
    error SpotLpTokenPriceNotSafe();

    event IncentiveSnapshot(
        uint256 totalApr,
        uint256 incentiveCredits,
        uint256 lastIncentiveTimestamp,
        bool decayState,
        uint256 decayInitTimestamp
    );

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseStatsCalculator(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes calldata initData) public virtual override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.underlyerStats, "underlyerStats");
        Errors.verifyNotZero(decodedInitData.boostedRewarder, "boostedRewarder");
        Errors.verifyNotZero(decodedInitData.boostedPosition, "boostedPosition");

        underlyerStats = IDexLSTStats(decodedInitData.underlyerStats);
        boostedRewarder = IReward(decodedInitData.boostedRewarder);
        boostedPosition = IPoolPositionSlim(decodedInitData.boostedPosition);
        pool = address(boostedPosition.pool());

        lastIncentiveTimestamp = block.timestamp;
        decayInitTimestamp = block.timestamp;

        decayState = false;

        _aprId = keccak256(abi.encode("incentive", decodedInitData.boostedRewarder));
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return address(boostedRewarder);
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IDexLSTStats
    function current() external returns (DexLSTStatsData memory dexLSTStatsData) {
        DexLSTStatsData memory data = underlyerStats.current();
        IReward.RewardInfo[] memory rewardInfo = boostedRewarder.rewardInfo();
        uint8 currentCredits = incentiveCredits;

        if (decayState) {
            // take required snaps as needed.
            uint256 totalAPR = _computeTotalAPR(rewardInfo, false);

            // Apply additional decay if APR is within tolerance
            // slither-disable-next-line incorrect-equality
            if ((totalAPR == 0) || totalAPR < (lastSnapshotTotalAPR + (lastSnapshotTotalAPR / 20))) {
                // slither-disable-start timestamp
                uint256 hoursPassed = (block.timestamp - decayInitTimestamp) / 3600;
                if (hoursPassed > 0) {
                    currentCredits = Stats.decayCredits(incentiveCredits, hoursPassed);
                }
                // slither-disable-end timestamp
            }
        }

        uint256[] memory annualizedRewardAmounts = new uint256[](rewardInfo.length - 1); // account for 0 slot
        uint40[] memory periodFinishForRewards = new uint40[](rewardInfo.length - 1);
        address[] memory rewardTokensToReturn = new address[](rewardInfo.length - 1); // copy into memory to return
        IReward.RewardInfo memory info;
        for (uint256 index = 0; index < rewardInfo.length - 1; ++index) {
            info = rewardInfo[index + 1];
            if (address(info.rewardToken) != address(0)) {
                annualizedRewardAmounts[index] = info.rewardRate * Stats.SECONDS_IN_YEAR;
                periodFinishForRewards[index] = uint40(info.finishAt);
                rewardTokensToReturn[index] = address(info.rewardToken);
            }
        }
        uint256 foundPeriodFinish = periodFinishForRewards[0];
        uint256 safeTotalSupplyOfActiveRewardToken = safeTotalSupplies[rewardTokensToReturn[0]];

        for (uint256 index = 0; index < rewardInfo.length - 1; ++index) {
            if (foundPeriodFinish > block.timestamp) {
                break;
            }
            if (periodFinishForRewards[index] > foundPeriodFinish) {
                foundPeriodFinish = periodFinishForRewards[index];
                safeTotalSupplyOfActiveRewardToken = safeTotalSupplies[rewardTokensToReturn[index]];
            }
        }

        data.stakingIncentiveStats = StakingIncentiveStats({
            safeTotalSupply: safeTotalSupplyOfActiveRewardToken,
            rewardTokens: rewardTokensToReturn,
            annualizedRewardAmounts: annualizedRewardAmounts,
            periodFinishForRewards: periodFinishForRewards,
            incentiveCredits: currentCredits
        });

        return data;
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view override returns (bool) {
        IReward.RewardInfo[] memory rewardInfo = boostedRewarder.rewardInfo();
        IReward.RewardInfo memory info;
        uint256 totalSupply = IERC20(address(boostedRewarder)).totalSupply();
        for (uint256 index = 1; index < rewardInfo.length; ++index) {
            info = rewardInfo[index];
            if (_shouldSnapshot(info, totalSupply)) {
                return true;
            }
        }

        // if no reward tokens need need a snapshot then return false
        return false;
    }

    function _snapshot() internal override {
        IReward.RewardInfo[] memory rewardInfo = boostedRewarder.rewardInfo();

        // Record a new snapshot of total APR across all rewarders
        // Also, triggers a new snapshot or finalize snapshot for total supply across all the rewarders
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign, reentrancy-eth
        lastSnapshotTotalAPR = _computeTotalAPR(rewardInfo, true);
        uint8 currentCredits = incentiveCredits;
        uint256 elapsedTime = block.timestamp - lastIncentiveTimestamp;

        // If APR is above a threshold and credits are below the cap and 1 day has passed since the last update
        // slither-disable-next-line timestamp
        if (lastSnapshotTotalAPR >= NON_TRIVIAL_ANNUAL_RATE && currentCredits < MAX_CREDITS && elapsedTime >= 1 days) {
            // If APR is above a threshold, increment credits based on time elapsed
            // Only give credit for whole days, so divide-before-multiply is desired
            // slither-disable-next-line divide-before-multiply
            uint256 credits = 12 * (elapsedTime / 1 days); // 12 credits for each day
            // avoids overflow errors if we miss a snapshot() for 21+ days
            // Increment credits, but cap at MAX_CREDITS
            incentiveCredits = uint8(Math.min(currentCredits + credits, MAX_CREDITS));
            // Update the last incentive timestamp to the current block's timestamp
            lastIncentiveTimestamp = block.timestamp;
            decayState = false;
        } else if (lastSnapshotTotalAPR >= NON_TRIVIAL_ANNUAL_RATE) {
            decayState = false;
        } else if (lastSnapshotTotalAPR < NON_TRIVIAL_ANNUAL_RATE) {
            // Set to decay incentive credits state since APR is 0 or near 0
            if (!decayState) {
                decayState = true;
                decayInitTimestamp = block.timestamp;
            } else {
                // If APR is below a threshold, decay credits based on time elapsed
                // slither-disable-start timestamp
                uint256 hoursPassed = (block.timestamp - decayInitTimestamp) / 3600;
                // slither-disable-end timestamp
                if (hoursPassed > 0 && decayState) {
                    incentiveCredits = Stats.decayCredits(currentCredits, hoursPassed);

                    // Update the incentive decay init timestamp to current timestamp
                    decayInitTimestamp = block.timestamp;
                }
            }
            // Update the last incentive timestamp to the current block's timestamp
            lastIncentiveTimestamp = block.timestamp;
        }

        // slither-disable-next-line reentrancy-events
        emit IncentiveSnapshot(
            lastSnapshotTotalAPR, incentiveCredits, lastIncentiveTimestamp, decayState, decayInitTimestamp
        );
    }

    /**
     * @notice Determines the snapshot status for a given rewarder.
     * @param info Information about the reward token and the rate of rewards
     * @return The snapshot status for the given rewarder, based on the last snapshot and current block time.
     */
    function _snapshotRewarderStatus(
        IReward.RewardInfo memory info
    ) public view returns (SnapshotStatus) {
        if (lastSnapshotRewardPerTokens[address(info.rewardToken)] == 0) {
            return SnapshotStatus.noSnapshot;
        }

        if (
            (
                info.rewardRate != lastSnapshotRewardRates[address(info.rewardToken)]
                    && lastSnapshotRewardRates[address(info.rewardToken)] != 0
            ) || (lastSnapshotRewardPerTokens[address(info.rewardToken)] > info.rewardPerTokenStored + 1)
        ) {
            /* @dev (lastSnapshotRewardPerTokens[address(info.rewardToken)] > info.rewardPerTokenStored + 1)
            this condition prevents underflow if a reward token is deleted, then added back at the same rewardRate
            but with a lower rewardPerTokenStored */

            // lastSnapshotRewardRates[info.rewardToken] can be zero before the first snapshot
            return SnapshotStatus.shouldRestart;
        }

        // slither-disable-next-line timestamp
        if (block.timestamp < lastSnapshotTimestamps[address(info.rewardToken)] + SNAPSHOT_INTERVAL) {
            return SnapshotStatus.tooSoon;
        }

        return SnapshotStatus.shouldFinalize;
    }

    function _shouldSnapshot(IReward.RewardInfo memory info, uint256 totalSupply) public view returns (bool) {
        SnapshotStatus status = _snapshotRewarderStatus(info);

        // If the status indicates we should finalize a snapshot, return true.
        if (status == SnapshotStatus.shouldFinalize || status == SnapshotStatus.shouldRestart) return true;

        // If it's too soon to take another snapshot, return false.
        if (status == SnapshotStatus.tooSoon) return false;

        // No further snapshots are needed after the period finishes.
        // slither-disable-next-line timestamp
        if (block.timestamp > info.finishAt) return false;

        // No further snapshots are needed if reward rate is zero.
        if (info.rewardRate == 0) return false;

        uint256 timeBetweenSnapshots = block.timestamp - lastSnapshotTimestamps[address(info.rewardToken)];

        // If more than 24 hours passed since the last snapshot, take another one.
        // slither-disable-next-line timestamp
        if (timeBetweenSnapshots > 24 hours) return true;

        // Snapshot if there's no supply and still time left in the period.
        if (totalSupply == 0) return true;

        // if _rewardRate differs by more than 5% from the last snapshot reward rate, take another snapshot.
        if (Stats.differsByMoreThanFivePercent(lastSnapshotRewardRates[address(info.rewardToken)], info.rewardRate)) {
            return true;
        }

        uint256 safeTotalSupply = safeTotalSupplies[address(info.rewardToken)];

        // slither-disable-next-line timestamp
        if (Stats.differsByMoreThanFivePercent(safeTotalSupply, totalSupply) && timeBetweenSnapshots > 6 hours) {
            return true;
        }

        return false;
    }

    function _snapshotRewarder(IReward.RewardInfo memory info, uint256 totalSupply) internal {
        if (totalSupply == 0) {
            safeTotalSupplies[address(info.rewardToken)] = 0;
            lastSnapshotRewardPerTokens[address(info.rewardToken)] = 0;
            lastSnapshotTimestamps[address(info.rewardToken)] = block.timestamp;
            return;
        }

        SnapshotStatus status = _snapshotRewarderStatus(info);

        // Initialization: When no snapshot exists, start a new snapshot.
        // Restart: If the reward rate changed, restart the snapshot process.
        if (status == SnapshotStatus.noSnapshot || status == SnapshotStatus.shouldRestart) {
            // Increase by one to ensure 0 is only used as an uninitialized value flag.
            lastSnapshotRewardPerTokens[address(info.rewardToken)] = info.rewardPerTokenStored + 1;
            lastSnapshotRewardRates[address(info.rewardToken)] = info.rewardRate;
            // slither-disable-next-line timestamp
            lastSnapshotTimestamps[address(info.rewardToken)] = block.timestamp;
            return;
        }

        // Finalization: If a snapshot exists, finalize by calculating the reward accrued
        // since initialization, then reset the snapshot state.
        if (status == SnapshotStatus.shouldFinalize) {
            uint256 lastSnapshotTimestamp = lastSnapshotTimestamps[address(info.rewardToken)];
            uint256 lastRewardPerToken = lastSnapshotRewardPerTokens[address(info.rewardToken)];
            // Subtract one, added during initialization, to ensure 0 is only used as an uninitialized value flag.
            uint256 diff = info.rewardPerTokenStored - (lastRewardPerToken - 1);
            // slither-disable-start timestamp
            uint256 timeBetweenSnapshots = block.timestamp - lastSnapshotTimestamp;
            if ((diff > 0) && (info.finishAt > block.timestamp)) {
                safeTotalSupplies[address(info.rewardToken)] = info.rewardRate * timeBetweenSnapshots * 1e18 / diff;
            }
            // slither-disable-end timestamp

            lastSnapshotRewardPerTokens[address(info.rewardToken)] = 0;
            lastSnapshotTimestamps[address(info.rewardToken)] = block.timestamp;
            return;
        }

        // It shouldn't be possible to reach this point.
        revert InvalidSnapshotStatus();
    }

    function _computeAPR(IReward.RewardInfo memory info, uint256 lpPrice) internal view returns (uint256) {
        // slither-disable-next-line timestamp
        if (block.timestamp > info.finishAt || info.rewardRate == 0) return 0;

        uint256 incentiveTokenPrice = _getIncentivePrice(address(info.rewardToken));
        uint256 numerator = info.rewardRate * Stats.SECONDS_IN_YEAR * incentiveTokenPrice * 1e18;
        uint256 denominator = safeTotalSupplies[address(info.rewardToken)] * lpPrice;

        return denominator == 0 ? 0 : numerator / denominator;
    }

    function _computeTotalAPR(
        IReward.RewardInfo[] memory rewardInfo,
        bool performSnapshot
    ) internal returns (uint256 totalApr) {
        IRootPriceOracle pricer = systemRegistry.rootPriceOracle();
        // slither-disable-next-line reentrancy-benign,unused-return
        (, uint256 lpSafePriceInQuote, bool isSpotSafe) =
            pricer.getRangePricesLP(address(boostedPosition), pool, address(systemRegistry.weth()));

        if (!isSpotSafe) {
            revert SpotLpTokenPriceNotSafe();
        }

        uint256 totalSupply = IERC20(address(boostedRewarder)).totalSupply();
        IReward.RewardInfo memory info;
        for (uint256 index = 0; index < rewardInfo.length; ++index) {
            info = rewardInfo[index];
            if (performSnapshot && _shouldSnapshot(info, totalSupply)) {
                _snapshotRewarder(info, totalSupply);
            }

            totalApr += _computeAPR(info, lpSafePriceInQuote);
        }
    }

    function _getIncentivePrice(
        address _token
    ) internal view returns (uint256) {
        IIncentivesPricingStats pricingStats = systemRegistry.incentivePricing();
        (uint256 fastPrice, uint256 slowPrice) = pricingStats.getPrice(_token, PRICE_STALE_CHECK);
        return Math.min(fastPrice, slowPrice);
    }

    function lpToken() public view returns (address) {
        return address(boostedPosition);
    }
}
