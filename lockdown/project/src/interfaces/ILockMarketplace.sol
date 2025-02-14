// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @title ILockMarketplace.sol
 *
 * @notice Interface for LockMarketplace.sol
 */

interface ILockMarketplace is IERC721Metadata {
    
    function mintWithUSDC(address to, uint256 usdcAmount) external returns (uint256);
    function pauseContract() external;
    function unpauseContract() external;
    function withdrawMintingProfit(address recipient) external;
    function initialize(address _lockToken, address _cUsdcAddress, address comptroller_) external;
    function getDeposit(address owner_, uint256 index) external view returns (uint256);
    function getDeposit(uint256 tokenId) external view returns (uint256);
    function stake(uint256 tokenId, uint256 usdcAmount) external;
    function unStake(address to, uint256 tokenId) external;
    function setMarketConditions(uint256 tokenPrice, uint256 stakePrice, uint256 mintFee) external;
    function startMarket(uint256 tokenPrice, uint256 stakePrice, uint256 mintFee) external;
    function getCUSDCMapping(address addr) external returns (uint256);
    function redeemCompoundRewards(uint256 tokenId) external returns (uint256);
    function isStaked(uint256 tokenId) external returns (bool);
    function setPrevOwner(uint256 tokenId, address prevOwner) external;
    function setStaked(uint256 tokenId, bool staked) external;
    function depositUSDC(uint256 tokenId,uint256 usdcAmount) external;
    function withdrawUSDC(uint256 tokenId_, uint256 amount_) external;
    function redeemCompoundRewards(uint256 tokenId, uint256 rewardAmount) external returns (uint256);
    function getAvailableRewards(address recipient) external returns (uint256);
    function initialMinNFTDeposit() external returns (uint256);
    function minimumStakePrice() external returns (uint256);
    function totalDeposits() external returns (uint256); 
}