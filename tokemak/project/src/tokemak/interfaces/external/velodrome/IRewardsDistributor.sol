// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase
// slither-disable-start naming-convention
interface IRewardsDistributor {
    function claim(
        uint256 _tokenId
    ) external returns (uint256);
    function claim_many(
        uint256[] memory _tokenIds
    ) external returns (bool);
}
// slither-disable-end naming-convention
