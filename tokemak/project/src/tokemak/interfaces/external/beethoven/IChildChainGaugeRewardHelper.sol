// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IRewardsOnlyGauge } from "src/tokemak/interfaces/external/beethoven/IRewardsOnlyGauge.sol";

//  solhint-disable max-line-length
/**
 * @dev based on the following abi
 * https://github.com/beethovenxfi/beets-frontend/blob/064f86d5d326f6fc4db13a320b923565a4fcfbfb/lib/abi/ChildChainGaugeRewardHelper.json
 */
interface IChildChainGaugeRewardHelper {
    /// @notice Claim rewards from a gauge
    function claimRewards(IRewardsOnlyGauge gauge, address user) external;
}
