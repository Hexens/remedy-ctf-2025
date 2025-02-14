// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import "src/openzeppelin-contracts/access/Ownable.sol";

contract AdminNFT is ERC1155, Ownable {
    address public bridgeContract;

    constructor(address _bridgeContract) ERC1155("") {
        bridgeContract = _bridgeContract;
    }

    // Modifier to restrict access to only the bridge contract
    modifier onlyBridge() {
        require(msg.sender == bridgeContract, "Caller is not the bridge contract");
        _;
    }

    // Function to set a new bridge contract (restricted to the owner)
    function setBridgeContract(address _bridgeContract) external onlyOwner {
        require(_bridgeContract != address(0), "Bridge contract address cannot be zero");
        bridgeContract = _bridgeContract;
    }

    // Mint function callable only by the bridge contract
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external onlyBridge {
        _mint(to, id, amount, data);
    }

    // Mint batch function callable only by the bridge contract
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external onlyBridge {
        _mintBatch(to, ids, amounts, data);
    }

    // Burn function callable only by the bridge contract
    function burn(address from, uint256 id, uint256 amount) external onlyBridge {
        _burn(from, id, amount);
    }

    // Burn batch function callable only by the bridge contract
    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) external onlyBridge {
        _burnBatch(from, ids, amounts);
    }
}
