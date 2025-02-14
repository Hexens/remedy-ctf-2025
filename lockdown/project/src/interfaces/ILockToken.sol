// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @title ILock.sol
 *
 * @notice Interface for LockToken.sol
 * largely inherits from openZeppelin IERC721Enumerable.sol
 * see https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/IERC721Enumerable.sol
 */

interface ILockToken is IERC721Metadata, IERC721Enumerable {

    function getMarketplace() external returns (address);
    function getTokenCounter() external returns (uint256);
    function requireApprovedOrOwner(address account, uint256 tokenId) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) external override;
    function mint(address to) external;
    function updateMarketplace(address __newMarketplace) external;
    function pause() external;
    function unpause() external;
}