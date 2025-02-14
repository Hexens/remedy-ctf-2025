// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity ^0.8.24;

import { PrimaryProdDataServiceConsumerBase } from
    "redstone-finance/data-services/PrimaryProdDataServiceConsumerBase.sol";

import { SystemComponent } from "src/tokemak/SystemComponent.sol";
import { SecurityBase } from "src/tokemak/security/SecurityBase.sol";
import { ISystemRegistry } from "src/tokemak/interfaces/ISystemRegistry.sol";
import { ISystemComponent } from "src/tokemak/interfaces/ISystemComponent.sol";
import { ICustomSetOracle } from "src/tokemak/interfaces/oracles/ICustomSetOracle.sol";
import { Errors } from "src/tokemak/utils/Errors.sol";
import { Roles } from "src/tokemak/libs/Roles.sol";

/**
 * @notice This contract is used to adapt the Redstone oracle payloads sent by our backend for the CustomSetOracle
 * updates.
 * The main logic is implemented in the updatePriceWithFeedId function.
 * The rest of the functions are used to register and manage the feedId to token address mapping and authorized signers
 * who we trust to sign the Redstone payload.
 * @dev This contract extends a hierarchy of Redstone contracts that are able to fetch the Redstone payload from the
 * transactions calldata.
 * ref: https://docs.redstone.finance/docs/get-started/models/redstone-pull/#manual-payload
 */
contract CustomRedStoneOracleAdapter is PrimaryProdDataServiceConsumerBase, SystemComponent, SecurityBase {
    event FeedIdRegistered(bytes32 indexed feedId, address indexed tokenAddress, bool ethQuoted, uint256 feedDecimals);
    event FeedIdRemoved(bytes32 indexed feedId);

    error TokenNotRegistered(bytes32 feedId, address tokenAddress);

    /// @dev Constant referenced from BaseOracleDenominations contract
    address public constant ETH_IN_USD = address(bytes20("ETH_IN_USD"));

    ICustomSetOracle public immutable customOracle;
    uint8 public uniqueSignersThreshold;

    struct FeedId {
        address tokenAddress;
        bool ethQuoted;
        uint8 feedDecimals;
    }

    /// @notice Mapping between a Redstone feedId and token address and if the price is quoted in ETH
    mapping(bytes32 => FeedId) public registeredFeedIds;

    /// @notice Mapping between an authorized signer address and its index for faster lookup
    mapping(address => uint8) internal signerAddressToIndex;

    /// @notice Array of authorized signers
    address[] private _authorizedSigners;

    constructor(
        ISystemRegistry _systemRegistry,
        address _customOracle,
        uint8 _uniqueSignersThreshold,
        address[] memory initAuthorizedSigners
    ) SystemComponent(_systemRegistry) SecurityBase(address(_systemRegistry.accessController())) {
        Errors.verifyNotZero(_customOracle, "customOracle");
        customOracle = ICustomSetOracle(_customOracle);

        // Verify that the custom oracle is from the same system registry as the adapter
        address customOracleSystemRegistry = ISystemComponent(_customOracle).getSystemRegistry();
        if (address(_systemRegistry) != customOracleSystemRegistry) {
            revert Errors.SystemMismatch(address(_systemRegistry), customOracleSystemRegistry);
        }

        uniqueSignersThreshold = _uniqueSignersThreshold;
        _initializeSignerAddressToIndex(initAuthorizedSigners);
    }

    /// @notice Returns array of authorized signer addresses
    /// @return Array of authorized signer addresses
    function authorizedSigners() external view returns (address[] memory) {
        return _authorizedSigners;
    }

    ///@notice Sets the price from extracted and validated Redstone payload
    function updatePriceWithFeedId(
        bytes32[] memory feedIds
    ) public hasRole(Roles.CUSTOM_ORACLE_EXECUTOR) {
        uint256 len = feedIds.length;
        Errors.verifyNotZero(len, "len");

        // Extract and validate the prices from the Redstone payload
        (uint256[] memory values, uint256 timestamp) = getOracleNumericValuesAndTimestampFromTxMsg(feedIds);

        // Call of RedstoneConsumerBase implementation of validateTimestamp
        validateTimestamp(timestamp);

        // Prepare the base tokens array
        address[] memory baseTokens = new address[](len);
        // Prepare the timestamps array and validate prices
        uint256[] memory queriedTimestamps = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            // Save token address from the registered mapping
            FeedId memory feedId = registeredFeedIds[feedIds[i]];
            if (feedId.tokenAddress == address(0)) {
                revert TokenNotRegistered(feedIds[i], feedId.tokenAddress);
            }
            baseTokens[i] = feedId.tokenAddress;

            // Validate the price
            Errors.verifyNotZero(values[i], "baseToken price");

            // Adjust the price from the feed decimals to 18 decimals
            uint8 feedDecimals = feedId.feedDecimals;
            if (feedDecimals < 18) {
                values[i] = values[i] * 10 ** (18 - feedDecimals);
            } else if (feedDecimals > 18) {
                values[i] = values[i] / 10 ** (feedDecimals - 18);
            }

            // Convert to ETH if the data feed price is not quoted in ETH
            if (!feedId.ethQuoted) {
                uint256 ethInUsd = systemRegistry.rootPriceOracle().getPriceInEth(ETH_IN_USD);
                values[i] = (values[i] * 1e18) / ethInUsd;
            }

            // Set the same timestamp from the Redstone payload for all base tokens
            queriedTimestamps[i] = timestamp / 1000; // adapted to seconds

            // Redstone allows, but validates are within tolerance, future timestamps.
            // We'll allow them as well, their validity will just be slightly shortened
            // slither-disable-next-line timestamp
            if (queriedTimestamps[i] > block.timestamp) {
                queriedTimestamps[i] = block.timestamp;
            }
        }
        // Set the price in the custom oracle
        customOracle.setPrices(baseTokens, values, queriedTimestamps);
    }

    ///@dev This is a default implementation as referenced in the RedstoneConsumerNumericMock contract
    function getUniqueSignersThreshold() public view virtual override returns (uint8) {
        return uniqueSignersThreshold;
    }

    /// @notice Sets the unique signers threshold
    /// @param _uniqueSignersThreshold The unique signers threshold to set
    function setUniqueSignersThreshold(
        uint8 _uniqueSignersThreshold
    ) external hasRole(Roles.ORACLE_MANAGER) {
        uniqueSignersThreshold = _uniqueSignersThreshold;
    }

    /// @notice Registers a mapping between a Redstone feedId and token address
    /// @param feedId The Redstone feedId to register
    /// @param tokenAddress The token address to map to
    function registerFeedId(
        bytes32 feedId,
        address tokenAddress,
        bool ethQuoted,
        uint8 feedDecimals
    ) external hasRole(Roles.ORACLE_MANAGER) {
        Errors.verifyNotZero(feedId, "feedId");
        Errors.verifyNotZero(address(tokenAddress), "tokenAddress");
        registeredFeedIds[feedId] = FeedId(tokenAddress, ethQuoted, feedDecimals);
        emit FeedIdRegistered(feedId, tokenAddress, ethQuoted, feedDecimals);
    }

    /// @notice Removes a mapping between a Redstone feedId and token address
    /// @param feedId The Redstone feedId to remove mapping for
    function removeFeedId(
        bytes32 feedId
    ) external hasRole(Roles.ORACLE_MANAGER) {
        delete registeredFeedIds[feedId];
        emit FeedIdRemoved(feedId);
    }

    /// @notice Registers authorized signers overriding the existing ones
    /// @param signerAddresses The signers to register
    function registerAuthorizedSigners(
        address[] memory signerAddresses
    ) public hasRole(Roles.ORACLE_MANAGER) {
        // Clear the existing authorized signers
        uint256 len = _authorizedSigners.length;
        for (uint256 i = 0; i < len; ++i) {
            //slither-disable-next-line costly-loop
            delete signerAddressToIndex[_authorizedSigners[i]];
        }
        // Register the new authorized signers
        _initializeSignerAddressToIndex(signerAddresses);
    }

    /// @notice Returns the index of an authorized signer
    /// @param signerAddress The signer address to get the index for
    /// @return The index of the signer
    function getAuthorisedSignerIndex(
        address signerAddress
    ) public view virtual override returns (uint8) {
        uint8 signerIndex = signerAddressToIndex[signerAddress];
        if (signerIndex == 0) {
            revert SignerNotAuthorised(signerAddress);
        }
        return signerIndex - 1; // We subtract 1 to avoid 0 index as a flag
    }

    function _initializeSignerAddressToIndex(
        address[] memory signerAddresses
    ) private {
        for (uint256 i = 0; i < signerAddresses.length; ++i) {
            address signerAddress = signerAddresses[i];
            Errors.verifyNotZero(signerAddress, "signerAddress");
            // We save the index + 1 to avoid 0 index
            // as it is used as a flag to check if the signer is authorized in getter function
            signerAddressToIndex[signerAddress] = uint8(i + 1);
        }
        // Set the new authorized signers array
        _authorizedSigners = signerAddresses;
    }
}
