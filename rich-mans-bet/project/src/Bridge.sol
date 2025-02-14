// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import "src/openzeppelin-contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "src/openzeppelin-contracts/access/Ownable.sol";
import "src/openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "src/AdminNFT.sol";

contract Bridge is ERC1155Receiver, Ownable {
    using ECDSA for bytes;
    using ECDSA for bytes32;

    uint256 public constant VALIDATOR_PRICE = 1000 ether;
    uint256 public constant NFT_WEIGHT = 50;
    uint256 public constant OWNER_WEIGHT = 10_000;

    uint256 public currentNftId = 1; // Tracks the next NFT ID to mint

    struct Validator {
        address addr;
        uint256 weight;
    }

    mapping(address => uint256) public validatorWeights; // For change bridge settings
    address[] public bridgeSettingValidators; // For change bridge settings
    uint256 public totalWeight;

    address[] public withdrawValidators; // Separate list for withdraw validators

    address public challengeContract;
    address public adminNftContract;
    uint96 public threshold;

    // Event for cross-chain ETH transfers
    event CrossChainMessage(uint256 amount, address indexed sender, string destinationChain, address destinationAddress);
    event EthDeposited(address indexed sender, uint256 amount);
    event EthWithdrawn(address indexed recipient, bool success, uint256 amount);
    event BridgeUpdated(address indexed challengeContract, address indexed adminNftContract, uint256 threshold);
    event AdminNFTMinted(address indexed to, uint256 tokenId);

    mapping(bytes32 => bool) public processedMessages; // Track processed cross-chain messages

    constructor(
        address _challengeContract,
        uint96 _threshold,
        address[] memory _withdrawValidators
    ) payable {
        require(_threshold >= 1, "Initial threshold must be above 1");
        require(_withdrawValidators.length > 0, "Withdraw validators list cannot be empty");

        challengeContract = _challengeContract;
        adminNftContract = address(new AdminNFT(address(this)));
        threshold = _threshold;
        withdrawValidators = _withdrawValidators;
        _mintAdminNFT();
        validatorWeights[msg.sender] = OWNER_WEIGHT;
        totalWeight += OWNER_WEIGHT;
    }

    // Modifier to restrict access to bridge setting validators
    modifier onlyValidator() {
        require(validatorWeights[msg.sender] > 0, "Caller is not a bridge setting validator");
        _;
    }

    modifier onlyAdminNft() {
        require(msg.sender == adminNftContract, "Only Admin NFT");
        _;
    }

    // Mint an ADMIN NFT for 1000 ETH
    function mintAdminNFT() external payable {
        require(msg.value == VALIDATOR_PRICE, "Incorrect value sent");
        _mintAdminNFT();
    }

    function _mintAdminNFT() private {
        uint256 tokenId = currentNftId;
        currentNftId += 1;
        AdminNFT(adminNftContract).mint(msg.sender, tokenId, 1, "");
        emit AdminNFTMinted(msg.sender, tokenId);
    }

    // Function to verify the challenge
    function verifyChallenge() external {
        (bool success, bytes memory data) = challengeContract.call(
            abi.encodeWithSignature("getChallengeStatus()")
        );
        require(success, "Failed to call challenge contract");

        (bool stage1Solved, bool stage2Solved, bool stage3Solved) = abi.decode(data, (bool, bool, bool));
        require(stage1Solved, "Stage 1 not solved");
        require(stage2Solved, "Stage 2 not solved");
        require(stage3Solved, "Stage 3 not solved");

        (success, ) = challengeContract.call(
            abi.encodeWithSignature("completeChallenge(address)", msg.sender)
        );
        require(success, "Failed to call challenge contract");
    }

    // Deposit ETH to bridge to another chain
    function depositEth(string memory destinationChain, address destinationAddress) external payable {
        require(msg.value > 0, "Amount must be greater than zero");

        // Emit an event to log the cross-chain ETH transfer
        emit CrossChainMessage(msg.value, msg.sender, destinationChain, destinationAddress);
        emit EthDeposited(msg.sender, msg.value);
    }

    // Withdraw ETH on this chain
    function withdrawEth(bytes32 messageHash, bytes[] calldata signatures, address receiver, uint amount, bytes calldata callback) external onlyValidator {
        require(amount > 0, "Amount must be greater than zero");
        require(!processedMessages[messageHash], "Message already processed");

        uint256 accumulatedWeight = 0;
        address lastSigner = address(0);

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = messageHash.toEthSignedMessageHash().recover(signatures[i]);

            require(signer != lastSigner, "Repeated signer");

            // Ensure signer is in the withdraw validator list
            bool isValidValidator = false;
            for (uint256 j = 0; j < withdrawValidators.length; j++) {
                if (withdrawValidators[j] == signer) {
                    isValidValidator = true;
                    break;
                }
            }

            require(isValidValidator, "Invalid withdraw validator");

            // Count each valid validator equally
            accumulatedWeight += 1;
            lastSigner = signer;
        }

        require(
            accumulatedWeight >= threshold,
            "Insufficient weight to process withdrawal"
        );

        // Mark the message as processed
        processedMessages[messageHash] = true;

        // Transfer ETH to the recipient
        if (amount > address(this).balance)
            amount = address(this).balance;
        (bool success, ) = payable(receiver).call{value: amount}(callback);

        emit EthWithdrawn(msg.sender, success, amount);
    }

    // Handle deposits of a single NFT and register/update validators for bridge settings
    function onERC1155Received(
        address,
        address from,
        uint256,
        uint256,
        bytes calldata
    ) external override onlyAdminNft returns (bytes4) {
        if (validatorWeights[from] == 0) {
            bridgeSettingValidators.push(from);
        }

        validatorWeights[from] += NFT_WEIGHT;
        totalWeight += NFT_WEIGHT;

        return this.onERC1155Received.selector;
    }

    // Handle batch deposits of NFTs and register/update validators for bridge settings
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata,
        bytes calldata
    ) external override onlyAdminNft returns (bytes4) {
        uint256 totalAddedWeight = 0;

        if (ids.length > 1) {
            for (uint256 i = 0; i < ids.length; i++) {
                totalAddedWeight += NFT_WEIGHT;
            }
        } else {
            totalAddedWeight = NFT_WEIGHT;
        }

        validatorWeights[from] += totalAddedWeight;
        totalWeight += totalAddedWeight;

        if (validatorWeights[from] == totalAddedWeight) {
            bridgeSettingValidators.push(from);
        }

        return this.onERC1155BatchReceived.selector;
    }

    // Function to validate a signed message for changing bridge settings
    function changeBridgeSettings(
        bytes calldata message,
        bytes[] calldata signatures
    ) external onlyValidator {
        uint256 accumulatedWeight = 0;
        address lastSigner = address(0);

        address newChallengeContract;
        address newAdminNftContract;
        uint256 newThreshold;

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = message.toEthSignedMessageHash().recover(signatures[i]);

            require(signer != lastSigner, "Repeated signer");

            if (validatorWeights[signer] > 0) {
                accumulatedWeight += validatorWeights[signer];
            }

            lastSigner = signer;
        }

        require(
            accumulatedWeight >= totalWeight / 2,
            "Insufficient weight to change settings"
        );

        // Decode new parameters from the message
        (newChallengeContract, newAdminNftContract, newThreshold) = abi.decode(
            abi.encodePacked(message),
            (address, address, uint256)
        );

        require(newThreshold > 1, "New threshold must be above 1");

        // Call internal function to update bridge settings
        _updateBridge(newChallengeContract, newAdminNftContract, newThreshold);
    }

    // Internal function to update bridge settings
    function _updateBridge(address newChallengeContract, address newAdminNftContract, uint256 newThreshold) internal {
        challengeContract = newChallengeContract;
        adminNftContract = newAdminNftContract;
        threshold = uint96(newThreshold);

        emit BridgeUpdated(newChallengeContract, newAdminNftContract, newThreshold);
    }
}
