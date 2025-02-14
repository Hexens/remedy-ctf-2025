// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "src/interfaces/ILockMarketplace.sol";

/**
 * @title LockToken.sol
 *
 * @notice ERC-721 compliant token for use in LockMarketplace
 * @dev Restricted to one LCK per wallet
 *
 */
contract LockToken is 
    ERC721, 
    ERC721Enumerable, 
    Pausable, 
    AccessControl,
    ReentrancyGuard {    

    uint256 public _tokenIdCounter;

    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");

    address private _marketplace;

    ILockMarketplace private _iLockMarketPlace;

    /**
     * @dev Constructor
     *
     * @notice only token contract admin may pause/unpause
     *  sets access control so only deployer/LockMarketPlace contract may call 
     *  sensitive functions.
     * @param __marketplace address of LockMarketPlace contract.
     */
    constructor(address __marketplace) ERC721("LOCK Token", "LCK") 
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _marketplace = __marketplace;
        _grantRole(MARKETPLACE_ROLE, _marketplace);
        _tokenIdCounter = 0;
    }

    /**
     * @notice only token contract admin may pause/unpause
     */ 
    function pause() 
    public 
    onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        _pause();
    }

    function unpause() 
    public 
    onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        _unpause();
    }

    /**
     * @notice only token contract owner can set new marketplace
     */ 
    function updateMarketplace(address __newMarketplace) 
    external 
    onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        _marketplace = __newMarketplace;
    }

    /**
     * @notice Returns current marketplace contract address
     */ 
    function getMarketplace() 
    external 
    returns (address) 
    {
        return _marketplace;
    } 

    /**
     * @notice Returns current token counter (current token ID/current supply)
     */ 
    function getTokenCounter() 
    external     view

    returns (uint256) 
    {
        return _tokenIdCounter;
    }

    /**
     * @notice Requires provided address to own or operate the token
     * 
     * @param account the address to check
     * @param tokenId the token ID
     */ 
    function requireApprovedOrOwner(address account, uint256 tokenId) 
    public 
    view 
    returns (bool) 
    {
       require(_isApprovedOrOwner(account, tokenId), 
       "Caller is not token owner or approved");
    }

    /**
     * @notice Only marketplace can directly mint new tokens.
     *
     * @param to the token recipient
     */  
    function mint(address to) 
    public 
    onlyRole(MARKETPLACE_ROLE) 
    {
        _requireZeroBalance(to);
        _tokenIdCounter += 1;
        _requireNotMinted(_tokenIdCounter);
        _safeMint(to, _tokenIdCounter);
    }

    // function transferFrom(
    //     address from, 
    //     address to, 
    //     uint256 tokenId) 
    // public
    // nonReentrant 
    // override(ERC721, IERC721)
    // {
    //     _beforeTokenTransfer(from, to, tokenId);
    //     super.transferFrom(from, to, tokenId);
    // }

    // function _update(address to, uint256 tokenId, address auth) 
    // internal 
    // override(ERC721, ERC721Enumerable) 
    // returns (address)   {
    //     return super._update(to, tokenId, auth);
    // }
    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable, AccessControl)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        _requireZeroBalance(to);
        require(from != to, "from == to"); 
        if(_ownerOf(tokenId) != address(0))
        {   
            if(from == _marketplace)
            {
                ILockMarketplace(_marketplace).setStaked(tokenId, false);
            } else
            {
                ILockMarketplace(_marketplace).setPrevOwner(tokenId, ownerOf(tokenId));
            }
            
            if(to == _marketplace)
            {
                ILockMarketplace(_marketplace).setStaked(tokenId, true);
            }
        }
    }
    
    /**
     * @notice Reverts when attempting to send a token to a wallet with an existing token,
     *  unless recipient is marketplace contract (to allow staking).
     *
     * @param to the token recipient
     */
    function _requireZeroBalance(address to) 
    internal 
    view 
    {
        if(to != _marketplace){     
            require(balanceOf(to) == 0, "Only one voucher per address");
        }
    }

    /**
     * @notice Reverts on token not existing
     *
     * @param tokenId token ID
     */
    function _requireNotMinted(uint256 tokenId) 
    internal 
    view 
    virtual 
    {
        require(_ownerOf(tokenId) == address(0), "Token already minted");
    }

    // function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
    //     super._increaseBalance(account, value);
    // }


}