// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/ILockMarketplace.sol";
import "src/interfaces/ILockToken.sol";
import "src/interfaces/ICERC20.sol";
import "src/interfaces/IComptroller.sol";
import "src/LockToken.sol";

/**
 * @notice Marketplace for users to mint, deposit USDC into, 
 *  stake, and reclaim USDC rewards using LOCK Tokens (LCK)
 *
 */
contract LockMarketplace is
    Ownable,
    Initializable,
    Pausable,
    ERC721Holder,    
    ReentrancyGuard {

    IERC20 private _usdc;
    ICERC20 private _cusdc;
    IComptroller private _comptroller;
    ILockToken private _iLockToken;

    mapping(uint256 => uint) private _deposits;
    mapping(uint256 => bool) private  _stakedTokens;
    mapping(uint256 => uint) private  _stakedAmounts;
    mapping(uint256 => address) private _stakedOwners;
    mapping(uint256 => address) private _prevOwners;
    mapping(address => uint256) private _rewardsBalance;
    mapping(address => uint256) private _cUSDCInterest;
    
    uint256 private mintingFee;
    uint256 private mintingProfit;

    uint256 public initialMinNFTDeposit;
    uint256 public minimumStakePrice;
    uint256 public totalDeposits;

    bool private _started = false;

    event Deposit(uint256 indexed id, uint256 amount);
    event Withdraw(uint256 indexed id, uint256 amount);
    event TransferCUSDC(address from, address to, uint256 amount);

    error ZeroAddress();
    error MarketAlreadyStarted();
    error MarketNotActive();
    error NonexistentToken();
    error OnlyToken();

    constructor() {}

    /**
     * @dev Contract initialization
     *
     * @param _LockToken LockToken address
     * @param _cUsdcAddress The CUSDC token contract address
     * @param comptroller_ Compound v2 comptroller address
     */
    function initialize(
        address _LockToken, 
        address _cUsdcAddress, 
        address comptroller_)
    external 
    initializer 
    onlyOwner 
    {
        if(_LockToken == address(0)) revert ZeroAddress();
        if(_cUsdcAddress == address(0)) revert ZeroAddress();
        if(comptroller_ == address(0)) revert ZeroAddress();
        _iLockToken = ILockToken(_LockToken);
        _comptroller = IComptroller(comptroller_);
        _cusdc = ICERC20(_cUsdcAddress);
        _usdc = IERC20(_cusdc.underlying());
    }

    modifier onlyDuringMarket() 
    {
        if(!_started) revert MarketNotActive();
        _;
    }

    modifier onlyToken() 
    {
        if(msg.sender != address(_iLockToken)) revert OnlyToken();
        _;
    }

    function enterMarketWithCUSDC() 
    external 
    onlyOwner 
    {
        address[] memory markets = new address[](1);
        markets[0] = address(_cusdc);
        _comptroller.enterMarkets(markets);
    }

    function setMarketConditions(
        uint256 initDeposit, 
        uint256 stakePrice, 
        uint256 mintFee) 
    public
    onlyOwner 
    {
        initialMinNFTDeposit = initDeposit;
        minimumStakePrice = stakePrice;
        mintingFee = mintFee;
    }

    function startMarket(
        uint256 initDeposit, 
        uint256 stakePrice, 
        uint256 mintFee) 
    external 
    whenNotPaused 
    onlyOwner 
    {
        if(_started) revert MarketAlreadyStarted();
        totalDeposits = 0;
        _started = true;
        setMarketConditions(initDeposit, stakePrice, mintFee);
    }

    function endMarket() 
    external 
    whenNotPaused 
    onlyDuringMarket
    onlyOwner 
    {
        _started = false;
    }

    function withdrawMintingProfit(address recipient) 
    external 
    onlyOwner 
    {
        _usdc.transferFrom(address(this), recipient, mintingProfit);
        mintingProfit = 0;
    }

    function mintWithUSDC(address to, uint256 usdcAmount) 
    external 
    whenNotPaused
    onlyDuringMarket 
    nonReentrant 
    returns (uint256)
    {
        require(usdcAmount >= initialMinNFTDeposit, "Mint amount less than minimum initial deposit");
        usdcAmount = _sub(usdcAmount, mintingFee);
        mintingProfit += mintingFee;
        uint256 nextTokenId = _iLockToken.getTokenCounter() + 1;
        _iLockToken.mint(to);
        _depositIntoNFT(nextTokenId, usdcAmount);
        _usdc.approve(address(this), usdcAmount + mintingFee);
        _usdc.transferFrom(msg.sender, address(this), usdcAmount + mintingFee);
        return nextTokenId;
    } 

    function depositUSDC(uint256 tokenId,uint256 usdcAmount) 
    external 
    whenNotPaused
    onlyDuringMarket
    nonReentrant  
    {
        require(usdcAmount != 0, "Cannot deposit 0 USDC");
        _iLockToken.requireApprovedOrOwner(msg.sender, tokenId);
        _depositIntoNFT(tokenId, usdcAmount);
        _usdc.approve(address(this), usdcAmount);
        _usdc.transferFrom(msg.sender, address(this), usdcAmount);
    }

    function withdrawUSDC(uint256 tokenId, uint256 amount) 
    external 
    whenNotPaused
    onlyDuringMarket 
    nonReentrant
    {
        _iLockToken.requireApprovedOrOwner(msg.sender, tokenId);
        require(!_stakedTokens[tokenId], "Token still staked");
        require(_deposits[tokenId] >= amount, "Withdrawal greater than deposited value");
        require(amount != 0, "Cannot withdraw 0 USDC");
        _withdrawOutOfNFT(tokenId, amount);
        _usdc.approve(address(this),  amount);
        _usdc.transferFrom(address(this), msg.sender, amount);
    }

    function stake(uint256 tokenId, uint256 usdcAmount) 
    external 
    whenNotPaused
    onlyDuringMarket
    nonReentrant 
    {
        _iLockToken.requireApprovedOrOwner(msg.sender, tokenId);
        require(!_stakedTokens[tokenId], "Token already staked");
        require(_deposits[tokenId] >= usdcAmount, "Not enough deposits"); 
        require(usdcAmount >= minimumStakePrice , "Insufficient stake amount");
        _stakedAmounts[tokenId] = usdcAmount;
        _stakedOwners[tokenId] =  msg.sender;
        _stakedTokens[tokenId] = true;
        _iLockToken.transferFrom(_iLockToken.ownerOf(tokenId), address(this), tokenId);
        _swapUSDCforCUSDC(_prevOwners[tokenId], usdcAmount, tokenId );
    }

    function unStake(address to, uint256 tokenId) 
    external 
    whenNotPaused
    onlyDuringMarket
    nonReentrant 
    { 
        require(_stakedTokens[tokenId], "Token not staked");
        require(_stakedOwners[tokenId] == msg.sender ||
        _prevOwners[tokenId] == msg.sender, "Caller is not token staker");        
        require(to != address(this), "Cannot unstake to marketplace");    
        require(_stakedAmounts[tokenId] >= 0, "Nothing to unstake");    
        delete _stakedOwners[tokenId];
        _iLockToken.safeTransferFrom(address(this), to, tokenId, "");
        _swapCUSDCforUSDC(_prevOwners[tokenId], tokenId);
        delete _stakedAmounts[tokenId];
    }

    function _swapUSDCforCUSDC(address recipient, uint256 usdcAmount, uint256 tokenId) 
    internal 
    returns (uint256) 
    {
        require(_deposits[tokenId] >=_stakedAmounts[tokenId] && 
        _stakedAmounts[tokenId] >= usdcAmount, "Minting more CUSDC than deposited USDC");
        uint256 contractUSDCBalBefore =_usdc.balanceOf(address(this));
        uint256 contractCUSDCBalBefore = _cusdc.balanceOf(address(this));
        _usdc.approve(address(_cusdc), usdcAmount);
        require(_cusdc.mint(usdcAmount) == 0, "Mint CUSDC failed");
        uint256 usdcDiff = _sub(contractUSDCBalBefore, _usdc.balanceOf(address(this)));
        _withdrawOutOfNFT(tokenId, usdcDiff);
        uint256 cusdcDiff = _sub(_cusdc.balanceOf(address(this)), contractCUSDCBalBefore);
        _cUSDCInterest[recipient] += cusdcDiff;
        _rewardsBalance[recipient] = _sub(_rewardsBalance[recipient], usdcDiff);
        return cusdcDiff;
    } 

    function _swapCUSDCforUSDC(address recipient,  uint256 tokenId) 
    internal 
    returns (uint256) 
    {
        uint256 contractCUSDCBalBefore = _cusdc.balanceOf(address(this));
        uint256 contractUSDCBalBefore = _usdc.balanceOf(address(this));
        require(_cusdc.redeem(_cUSDCInterest[_iLockToken.ownerOf(tokenId)])==0, "Redeem CUSDC Failed");
        uint256 usdcDiff = _sub(_usdc.balanceOf(address(this)), contractUSDCBalBefore);
        _depositIntoNFT(tokenId, usdcDiff);
        _rewardsBalance[recipient] += usdcDiff;
        uint256 cusdcDiff = _sub(contractCUSDCBalBefore, _cusdc.balanceOf(address(this)));
        _cUSDCInterest[recipient] = _sub(_cUSDCInterest[recipient], cusdcDiff);        
        return usdcDiff;
    }

    function redeemCompoundRewards(uint256 tokenId, uint256 rewardAmount) 
    external
    whenNotPaused
    onlyDuringMarket
    nonReentrant 
    returns (uint256)
    {
        _iLockToken.requireApprovedOrOwner(msg.sender, tokenId);
        require(!_stakedTokens[tokenId], "Token still staked");
        require(rewardAmount > 0, "No Rewards");
        require(_rewardsBalance[msg.sender] >= rewardAmount, "Redemming more rewards than available for account");
        _withdrawOutOfNFT(tokenId, rewardAmount);
        _usdc.approve(address(this), rewardAmount);
        uint256 contractUSDCBalBefore = _usdc.balanceOf(address(this));
        _usdc.transferFrom(address(this), msg.sender,rewardAmount);
        uint256 usdcReward = _sub(contractUSDCBalBefore, _usdc.balanceOf(address(this)));
        _rewardsBalance[msg.sender] = _sub(_rewardsBalance[msg.sender], usdcReward);
        return usdcReward;
    }

    function setPrevOwner(uint256 tokenId, address prevOwner) 
    public 
    onlyToken
    {
        _prevOwners[tokenId] = prevOwner;
    }

    function setStaked(uint256 tokenId, bool staked) 
    public 
    onlyToken
    {
        _stakedTokens[tokenId] =  staked;
    }

    function isStaked(uint256 tokenId)
    external
    view
    returns (bool)
    {
        return _stakedTokens[tokenId];
    }

    function getDeposit(uint256 tokenId) 
    public    
    view
    returns (uint256)
    {
        return _deposits[tokenId] ;
    }

    function getAvailableRewards(address _address) 
    public    
    view
    returns (uint256)
    {
        return _rewardsBalance[_address] ;
    }

    function _depositIntoNFT(uint256 tokenId, uint256 value) 
    internal 
    {
        if(tokenId == 0) revert NonexistentToken();
        _deposits[tokenId] += value;
        totalDeposits += value; 
        emit Deposit(tokenId, value);
    }

    function _withdrawOutOfNFT(uint256 tokenId, uint256 value) 
    internal 
    {
        if(tokenId == 0) revert NonexistentToken();
        _deposits[tokenId] = _sub(_deposits[tokenId], value);
        totalDeposits = _sub(totalDeposits, value);
        emit Withdraw(tokenId, value);
    }

    function _sub(uint256 a, uint256 b) 
    internal
    pure 
    returns (uint256)
    {
        return (a >= b ? (a-= b) : 0);
    }

    function pauseContract() 
    external 
    onlyOwner 
    {
        _pause();
    }

    function unpauseContract() 
    external 
    onlyOwner 
    {
        _unpause();
    }

}