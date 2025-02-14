// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity ^0.8.24;

// solhint-disable max-states-count

import { IDexLSTStats } from "src/tokemak/interfaces/stats/IDexLSTStats.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { BaseStatsCalculator } from "src/tokemak/stats/calculators/base/BaseStatsCalculator.sol";
import { IPool } from "src/tokemak/interfaces/external/aerodrome/IPool.sol";
import { IAerodromeGauge } from "src/tokemak/interfaces/external/aerodrome/IAerodromeGauge.sol";
import { IStatsCalculator } from "src/tokemak/interfaces/stats/IStatsCalculator.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { ILSTStats } from "src/tokemak/interfaces/stats/ILSTStats.sol";
import { IIncentivesPricingStats } from "src/tokemak/interfaces/stats/IIncentivesPricingStats.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";

import { Stats } from "src/tokemak/stats/Stats.sol";

contract AerodromeStakingIncentiveCalculator is IDexLSTStats, BaseStatsCalculator {
    /// @notice The stats contracts for the underlying LSTs
    /// @return the LST stats contract for the specified index
    ILSTStats[2] public lstStats;

    /// @notice The addresses of the pools reserve tokens
    /// @return the reserve token address for the specified index
    address[2] public reserveTokens;

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
    uint256 public constant SNAPSHOT_INTERVAL = 1 hours;

    /// @dev Non-trivial annual rate set at 0.5% (in fixed point format 1e18 = 1).
    uint256 public constant NON_TRIVIAL_ANNUAL_RATE = 5e15;

    /// @dev Duration after which a price/data becomes stale.
    uint40 public constant PRICE_STALE_CHECK = 12 hours;

    /// @dev Cap on allowable credits in the system.
    uint8 public constant MAX_CREDITS = 168;

    /// @notice The last time a snapshot was taken
    uint256 public lastSnapshotTimestamp;

    /// @notice Gauge reward rate in AERO at the time the last snapshot was taken
    uint256 public lastSnapshotRewardRate;

    /// @notice Gauge.rewardPerToken() in AERO at the time the last snapshot was taken
    uint256 public lastSnapshotRewardPerToken;

    /// @notice The token that reward tokens are issued in. AERO for Aerodrome
    address public rewardToken;

    /// @notice Time-weighted average total supply to prevent spikes/attacks from impacting rebalancing
    uint256 public safeTotalSupply;

    /// @notice Address of the sAMM or vAMM pool. The pool is also the lpToken
    IPool public pool;

    /// @notice Associated gauge for the pool where lp tokens are staked
    IAerodromeGauge public gauge;

    /// @notice AerodromeStakingDexCalculator of the associated pool
    IDexLSTStats public underlyerStats;

    bytes32 internal _aprId;

    error InvalidSnapshotStatus();
    error shouldNotResetCalculator();
    error SpotLpTokenPriceNotSafe();
    error GaugePoolMismatch();
    error GaugeNotForLegitimatePool();
    error RewardTokenNot18Decimals();

    event IncentiveSnapshot(
        uint256 totalApr,
        uint256 incentiveCredits,
        uint256 lastIncentiveTimestamp,
        bool decayState,
        uint256 decayInitTimestamp
    );

    event RewarderSafeTotalSupplySnapshot(
        address rewarder,
        uint256 rewardRate,
        uint256 timeBetweenSnapshots,
        uint256 rewardsAccruedPerToken,
        uint256 safeTotalSupply
    );

    struct InitData {
        address poolAddress;
        address gaugeAddress;
        address underlyerStats;
    }

    constructor(
        ISystemRegistry _systemRegistry
    ) BaseStatsCalculator(_systemRegistry) { }

    /// @inheritdoc IStatsCalculator
    function initialize(bytes32[] calldata, bytes calldata initData) external virtual override initializer {
        InitData memory decodedInitData = abi.decode(initData, (InitData));

        Errors.verifyNotZero(decodedInitData.poolAddress, "poolAddress");
        Errors.verifyNotZero(decodedInitData.gaugeAddress, "gaugeAddress");
        Errors.verifyNotZero(decodedInitData.underlyerStats, "underlyerStats");

        pool = IPool(decodedInitData.poolAddress);
        gauge = IAerodromeGauge(decodedInitData.gaugeAddress);
        underlyerStats = IDexLSTStats(decodedInitData.underlyerStats);

        rewardToken = gauge.rewardToken();
        reserveTokens[0] = pool.token0();
        reserveTokens[1] = pool.token1();
        _aprId = keccak256(abi.encode("aerodromeSVAmm", decodedInitData.poolAddress, decodedInitData.gaugeAddress));

        if (IERC20Metadata(rewardToken).decimals() != 18) {
            // Incentive APR will not scale correctly unless the rewardToken has 18 decimals
            revert RewardTokenNot18Decimals();
        }

        if (gauge.stakingToken() != decodedInitData.poolAddress) {
            revert GaugePoolMismatch();
        }

        if (!gauge.isPool()) {
            revert GaugeNotForLegitimatePool();
        }

        lastIncentiveTimestamp = block.timestamp;
        decayInitTimestamp = block.timestamp;
        decayState = false;
    }

    /// @inheritdoc IStatsCalculator
    function getAddressId() external view returns (address) {
        return rewardToken;
    }

    /// @inheritdoc IStatsCalculator
    function getAprId() external view returns (bytes32) {
        return _aprId;
    }

    /// @inheritdoc IDexLSTStats
    function current() external virtual returns (DexLSTStatsData memory) {
        // Fetch base stats
        DexLSTStatsData memory data = underlyerStats.current();

        // Length 1 because LPs only earn AERO emissions when staking their LP tokens
        uint256[] memory annualizedRewardAmounts = new uint256[](1);
        uint40[] memory periodFinishForRewards = new uint40[](1);
        address[] memory rewardTokensToReturn = new address[](1);

        uint8 currentCredits = incentiveCredits;

        annualizedRewardAmounts[0] = gauge.rewardRate() * Stats.SECONDS_IN_YEAR;
        periodFinishForRewards[0] = uint40(gauge.periodFinish());
        rewardTokensToReturn[0] = rewardToken;

        // Determine if incentive credits earned should continue to be decayed
        if (decayState) {
            uint256 totalAPR = _computeTotalAPR(false);

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

        data.stakingIncentiveStats = StakingIncentiveStats({
            safeTotalSupply: safeTotalSupply,
            rewardTokens: rewardTokensToReturn,
            annualizedRewardAmounts: annualizedRewardAmounts,
            periodFinishForRewards: periodFinishForRewards,
            incentiveCredits: currentCredits
        });

        return data;
    }

    /// @inheritdoc IStatsCalculator
    function shouldSnapshot() public view override returns (bool) {
        uint256 currentRewardRate = gauge.rewardRate();
        uint256 periodFinish = gauge.periodFinish();
        uint256 totalSupply = gauge.totalSupply();

        SnapshotStatus status = _getSnapshotStatus(currentRewardRate);

        // If the status indicates we should finalize a snapshot, return true.
        if (status == SnapshotStatus.shouldFinalize || status == SnapshotStatus.shouldRestart) return true;

        // If it's too soon to take another snapshot, return false.
        if (status == SnapshotStatus.tooSoon) return false;

        uint256 timeBetweenSnapshots = block.timestamp - lastSnapshotTimestamp;
        // If more than 24 hours passed since the last snapshot, take another one.
        // slither-disable-next-line timestamp
        if (timeBetweenSnapshots > 24 hours) return true;

        // No further snapshots are needed after the period finishes.
        // slither-disable-next-line timestamp
        if (block.timestamp > periodFinish) return false;

        // No further snapshots are needed if reward rate is zero.
        if (currentRewardRate == 0) return false;

        // Snapshot if there's no supply and still time left in the period.
        if (totalSupply == 0) return true;

        // if _rewardRate differs by more than 5% from the last snapshot reward rate, take another snapshot.
        if (Stats.differsByMoreThanFivePercent(lastSnapshotRewardRate, currentRewardRate)) {
            return true;
        }

        // slither-disable-next-line timestamp
        if (Stats.differsByMoreThanFivePercent(safeTotalSupply, totalSupply) && timeBetweenSnapshots > 6 hours) {
            return true;
        }

        return false;
    }

    /// @inheritdoc BaseStatsCalculator
    function _snapshot() internal override {
        // slither-disable-start line reentrancy-no-eth
        lastSnapshotTotalAPR = _computeTotalAPR(true);
        // slither-disable-end line reentrancy-no-eth
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

    function _getSnapshotStatus(
        uint256 currentRewardRate
    ) internal view returns (SnapshotStatus) {
        if (lastSnapshotRewardPerToken == 0) {
            return SnapshotStatus.noSnapshot;
        }
        if (currentRewardRate != lastSnapshotRewardRate && lastSnapshotRewardRate != 0) {
            // lastSnapshotRewardRate can be zero before the first snapshot or after a finalizing snapshot
            return SnapshotStatus.shouldRestart;
        }

        // slither-disable-next-line timestamp
        if (block.timestamp < lastSnapshotTimestamp + SNAPSHOT_INTERVAL) {
            return SnapshotStatus.tooSoon;
        }

        return SnapshotStatus.shouldFinalize;
    }

    function _snapshotRewarder() internal {
        // Aerodrome LPs only have a single rewarder that emits AERO.
        uint256 totalSupply = gauge.totalSupply();

        if (totalSupply == 0) {
            safeTotalSupply = 0;
            lastSnapshotRewardPerToken = 0;
            lastSnapshotTimestamp = block.timestamp;

            return;
        }
        uint256 currentRewardRate = gauge.rewardRate();
        // using rewardPerToken() instead of rewardPerTokenStored()
        // because on the Gauge.sol contracts rewardPerToken() accounts for the rewards earned since the last time
        // rewardPerTokenStored was updated
        uint256 rewardPerToken = gauge.rewardPerToken();
        uint256 periodFinish = gauge.periodFinish();

        SnapshotStatus status = _getSnapshotStatus(currentRewardRate);

        // Initialization: When no snapshot exists, start a new snapshot.
        // Restart: If the reward rate changed, restart the snapshot process.
        if (status == SnapshotStatus.noSnapshot || status == SnapshotStatus.shouldRestart) {
            // Increase by one to ensure 0 is only used as an uninitialized value flag.
            lastSnapshotRewardPerToken = rewardPerToken + 1;
            lastSnapshotRewardRate = currentRewardRate;
            lastSnapshotTimestamp = block.timestamp;

            return;
        }

        // Finalization: If a snapshot exists, finalize by calculating the reward accrued
        // since initialization, then reset the snapshot state.
        if (status == SnapshotStatus.shouldFinalize) {
            // Subtract one, added during initialization, to ensure 0 is only used as an uninitialized value flag.
            uint256 diff = rewardPerToken - (lastSnapshotRewardPerToken - 1);
            // slither-disable-start timestamp
            uint256 timeBetweenSnapshots = block.timestamp - lastSnapshotTimestamp;
            if ((diff > 0) && (periodFinish > block.timestamp)) {
                safeTotalSupply = currentRewardRate * timeBetweenSnapshots * 1e18 / diff;
            }
            // slither-disable-end timestamp

            lastSnapshotRewardPerToken = 0;
            lastSnapshotTimestamp = block.timestamp;
            // slither-disable-start reentrancy-events
            emit RewarderSafeTotalSupplySnapshot(
                address(gauge), currentRewardRate, timeBetweenSnapshots, diff, safeTotalSupply
            );
            // slither-disable-end reentrancy-events
            return;
        }

        // It shouldn't be possible to reach this point.
        revert InvalidSnapshotStatus();
    }

    function _getIncentivePrice(
        address _token
    ) internal view returns (uint256) {
        IIncentivesPricingStats pricingStats = systemRegistry.incentivePricing();
        (uint256 fastPrice, uint256 slowPrice) = pricingStats.getPrice(_token, PRICE_STALE_CHECK);
        return Math.min(fastPrice, slowPrice);
    }

    function _getLpTokenPriceInEth() internal returns (uint256) {
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
        (uint256 spotPrice, uint256 safePrice, bool isSpotSafe) = systemRegistry.rootPriceOracle().getRangePricesLP(
            address(pool), address(pool), address(systemRegistry.weth())
        );

        if (!isSpotSafe) {
            revert Errors.UnsafePrice(address(pool), spotPrice, safePrice);
        }

        return safePrice;
    }

    function _computeTotalAPR(
        bool performSnapshot
    ) internal returns (uint256 apr) {
        if (performSnapshot) {
            _snapshotRewarder();
        }

        // slither-disable-next-line reentrancy-no-eth
        uint256 lpPrice = _getLpTokenPriceInEth();
        uint256 rewardRate = gauge.rewardRate();
        uint256 periodFinish = gauge.periodFinish();
        apr = _computeAPR(lpPrice, rewardRate, periodFinish);
    }

    function _computeAPR(uint256 lpPrice, uint256 rewardRate, uint256 periodFinish) internal view returns (uint256) {
        // slither-disable-start incorrect-equality
        // slither-disable-next-line timestamp
        if (block.timestamp > periodFinish || rewardRate == 0) return 0;
        // slither-disable-end incorrect-equality

        uint256 incentiveTokenPrice = _getIncentivePrice(rewardToken);
        uint256 numerator = rewardRate * Stats.SECONDS_IN_YEAR * incentiveTokenPrice * 1e18;
        uint256 denominator = safeTotalSupply * lpPrice;

        return denominator == 0 ? 0 : numerator / denominator;
    }
}
