// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC721Enumerable } from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface INFTPool is IERC721Enumerable {
    function exists(
        uint256 tokenId
    ) external view returns (bool);
    function hasDeposits() external view returns (bool);
    function getPoolInfo()
        external
        view
        returns (
            address lpToken,
            address grailToken,
            address sbtToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        );
    function getStakingPosition(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );

    function boost(uint256 userAddress, uint256 amount) external;
    function unboost(uint256 userAddress, uint256 amount) external;

    /**
     * @dev Harvest from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function harvestPosition(
        uint256 tokenId
    ) external;

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     * spNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external;
}
