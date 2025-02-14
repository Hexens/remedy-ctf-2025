// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PackedUint128Math} from "@trader-joe/libraries/math/PackedUint128Math.sol";
import {LBPair} from "@trader-joe/LBPair.sol";
import {BinHelper} from "@trader-joe/libraries/BinHelper.sol";
import {Uint256x256Math} from "@trader-joe/libraries/math/Uint256x256Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract JoeLending is ERC1155, ReentrancyGuard, Ownable {
    using Math for uint256;
    using BinHelper for bytes32;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using Uint256x256Math for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    event Deposited(address indexed user, uint256[] ids, uint256[] amounts);
    event Redeemed(address indexed user, uint256[] ids, uint256[] amounts);
    event Burned(address indexed user, uint256[] ids, uint256[] amounts);

    enum RedeemOrborrow {
        REDEEM,
        BORROW
    }

    // Health factor
    uint256 public constant BASE_HEALTH_FACTOR = 1.25e18;
    // Collateral factor
    uint256 public constant COLLATERAL_FACTOR = 0.8e18;
    // Interest rate
    uint256 public constant INTEREST_RATE = 0.05e18;
    // Exponent scale
    uint256 public constant _expScale = 1e18;
    // Initial exchange rate
    uint256 public immutable _initialExchangeRate;

    // Price oracle
    mapping(IERC20 => address) public _priceOracles;
    // Borrowable token
    IERC20 public USDJ;
    // LBPair
    LBPair public _lbPair;
    // LBPair x decimals offset
    uint256 public _xOffset;
    // LBPair y decimals offset
    uint256 public _yOffset;

    // User's borrowed LBPair amount
    mapping(address => mapping(uint256 => uint256)) public _borrowedLb;
    // User's borrowed USDJ amount
    mapping(address => mapping(uint256 => uint256)) public _borrowedUsdj;
    // User's borrowed LBPair ids
    mapping(address => EnumerableSet.UintSet) internal _borrowedIds;
    // User's collateral LBPair ids
    mapping(address => EnumerableSet.UintSet) internal _collateralIds;
    // User's last interest accrual timestamp
    mapping(address => mapping(uint256 => uint256)) public _accrualTimestamp;
    // User's last interest accrued
    mapping(address => mapping(uint256 => uint256)) public _accruedInterest;

    // Total LBPair balance
    mapping(uint256 => uint256) public _totalLb;
    // Total Minted supply
    mapping(uint256 => uint256) public _totalSupplies;
    // Total borrowed LBPair amount
    mapping(uint256 => uint256) public _totalBorrowedLb;
    // Total borrowed USDJ amount
    mapping(uint256 => uint256) public _totalBorrowedUsdj;
    // Accrual timestamp
    mapping(uint256 => uint256) public _totalAccrualTimestamp;

    constructor(IERC20 usdj, address lbPair, uint256 xOffset, uint256 yOffset, uint256 initialExchangeRate)
        ERC1155("")
        Ownable(msg.sender)
    {
        USDJ = usdj;
        _lbPair = LBPair(lbPair);
        _xOffset = xOffset;
        _yOffset = yOffset;
        _initialExchangeRate = initialExchangeRate;
    }

    /**
     * @notice Deposit LBPair tokens
     * @param ids The ids of Collateral LBPair Tokens
     * @param amounts The amounts of the LBPair tokens to deposit
     */
    function deposit(uint256[] calldata ids, uint256[] calldata amounts) external nonReentrant {
        _processMintAndDeposit(msg.sender, ids, amounts);
        emit Deposited(msg.sender, ids, amounts);
    }

    function _processMintAndDeposit(address to, uint256[] memory ids, uint256[] memory amounts) internal {
        require(ids.length == amounts.length, "invalid deposit param length");

        uint256 exchangeRateMantissa;
        uint256[] memory mintTokens = new uint256[](ids.length);

        for (uint256 i; i < ids.length; i++) {
            _accrueInterest(ids[i]);
            _incurInterest(to, ids[i]);
            exchangeRateMantissa = _getExchangeRateMantissa(ids[i]);
            mintTokens[i] = amounts[i] * _expScale / exchangeRateMantissa;
            _totalSupplies[ids[i]] += mintTokens[i];
            _totalLb[ids[i]] += amounts[i];
            _collateralIds[to].add(ids[i]);
        }

        _lbPair.batchTransferFrom(to, address(this), ids, amounts);

        for (uint256 i; i < ids.length; i++) {
            _mint(to, ids[i], mintTokens[i], "");
        }

        return;
    }

    /**
     * @notice Burn LBPair tokens
     * @param ids The ids of Collateral LBPair Tokens
     * @param tokensOut The amounts of the Lending tokens to burn
     */
    function burn(uint256[] calldata ids, uint256[] calldata tokensOut) external nonReentrant {
        uint256[] memory amountsOut;
        _processBurnAndRedeem(msg.sender, ids, tokensOut, amountsOut);

        emit Burned(msg.sender, ids, amountsOut);
    }

    /**
     * @notice Redeem LBPair tokens
     * @param ids The ids of Collateral LBPair Tokens
     * @param amountsOut The amounts of the LBPair tokens to redeem
     */
    function redeem(uint256[] calldata ids, uint256[] calldata amountsOut) external nonReentrant {
        uint256[] memory tokensOut;
        _processBurnAndRedeem(msg.sender, ids, tokensOut, amountsOut);

        emit Redeemed(msg.sender, ids, amountsOut);
    }

    function _processBurnAndRedeem(
        address from,
        uint256[] memory ids,
        uint256[] memory tokensOut,
        uint256[] memory amountsOut
    ) internal {
        require(ids.length == tokensOut.length || ids.length == amountsOut.length, "invalid burn param length");
        require(tokensOut.length == 0 || amountsOut.length == 0, "one of tokensOut or amountsOut must be zero");
        require(tokensOut.length != amountsOut.length, "only one of tokensOut or amountsOut must be zero");

        uint256 exchangeRateMantissa;

        if (tokensOut.length > 0) {
            amountsOut = new uint256[](ids.length);
            for (uint256 i; i < ids.length; i++) {
                _accrueInterest(ids[i]);
                _incurInterest(from, ids[i]);
                exchangeRateMantissa = _getExchangeRateMantissa(ids[i]);
                amountsOut[i] = ((tokensOut[i] * exchangeRateMantissa + 1) / _expScale) - 1;
            }
        } else {
            tokensOut = new uint256[](ids.length);
            for (uint256 i; i < ids.length; i++) {
                _accrueInterest(ids[i]);
                _incurInterest(from, ids[i]);
                exchangeRateMantissa = _getExchangeRateMantissa(ids[i]);
                tokensOut[i] = amountsOut[i] * _expScale / exchangeRateMantissa;
            }
        }

        (, uint256 shortfall) = hypotheticalHealthCheck(from, ids, tokensOut, RedeemOrborrow.REDEEM);
        require(shortfall == 0, "redeem or burn hypotheticalHealthCheck failed");

        for (uint256 i; i < ids.length; i++) {
            _totalSupplies[ids[i]] -= tokensOut[i];
            _totalLb[ids[i]] -= amountsOut[i] > _totalLb[ids[i]] ? _totalLb[ids[i]] : amountsOut[i];
            _burn(from, ids[i], tokensOut[i]);
        }

        //require(_getHealthFactorMantissa(from) >= BASE_HEALTH_FACTOR, "health factor too low");

        _lbPair.batchTransferFrom(address(this), from, ids, amountsOut);
    }

    /**
     * @notice Borrow USDJ
     * @param ids The ids of Collateral LBPair Tokens
     * @param amounts The amounts of the USDJ to borrow
     */
    function borrow(uint256[] memory ids, uint256[] memory amounts) external nonReentrant {
        _borrow(msg.sender, ids, amounts);
    }

    /**
     * @notice Internal function to borrow USDJ
     * @param ids The ids of Collateral LBPair Tokens
     * @param amounts The amounts of the USDJ to borrow
     */
    function _borrow(address to, uint256[] memory ids, uint256[] memory amounts) internal {
        require(ids.length == amounts.length, "invalid borrow param length");
        (, uint256 shortfall) = hypotheticalHealthCheck(to, ids, amounts, RedeemOrborrow.BORROW);
        require(shortfall == 0, "borrow hypotheticalHealthCheck failed");
        uint256 usdjToTransfer = 0;
        for (uint256 i; i < ids.length; i++) {
            _accrueInterest(ids[i]);
            _incurInterest(to, ids[i]);
            _borrowedIds[to].add(ids[i]);
            uint256 borrowWorthMantissa = getAssetPrice(USDJ) * amounts[i];
            uint256 lbBalance = (balanceOf(to, ids[i]) * _getExchangeRateMantissa(ids[i]) / _expScale);
            uint256 collateralWorthMantissa = _getLiquidityValueMantissa(ids[i], lbBalance);
            uint256 lbAmount =
                (borrowWorthMantissa * lbBalance + (collateralWorthMantissa - 1)) / collateralWorthMantissa;
            _borrowedLb[to][ids[i]] += lbAmount;
            _borrowedUsdj[to][ids[i]] += amounts[i];
            _totalBorrowedLb[ids[i]] += lbAmount;
            _totalLb[ids[i]] -= lbAmount;
            _totalBorrowedUsdj[ids[i]] += amounts[i];
            usdjToTransfer += amounts[i];
        }

        USDJ.transfer(to, usdjToTransfer);
    }

    /**
     * @notice Repay USDJ
     * @param ids The ids of Collateral LBPair Tokens
     * @param amounts The amounts of the USDJ to repay
     */
    function repay(uint256[] calldata ids, uint256[] calldata amounts) external nonReentrant {
        _repay(msg.sender, ids, amounts);
    }

    function _repay(address to, uint256[] calldata ids, uint256[] calldata amounts) internal {
        require(ids.length == amounts.length, "invalid repay param length");

        uint256 usdjToTransfer = 0;
        uint256[] memory tokenAmount = new uint256[](ids.length);
        for (uint256 i; i < ids.length; i++) {
            _accrueInterest(ids[i]);
            _incurInterest(to, ids[i]);

            uint256 repayLb = _borrowedLb[to][ids[i]] * amounts[i] / _borrowedUsdj[to][ids[i]];
            uint256 interestLb = _accruedInterest[to][ids[i]] * amounts[i] / _borrowedUsdj[to][ids[i]];
            tokenAmount[i] = interestLb * _expScale / _getExchangeRateMantissa(ids[i]);

            _accruedInterest[to][ids[i]] -= interestLb;
            _borrowedLb[to][ids[i]] -= repayLb;
            _borrowedUsdj[to][ids[i]] -= amounts[i];
            _totalBorrowedLb[ids[i]] -= repayLb;
            _totalBorrowedUsdj[ids[i]] -= amounts[i];
            _totalLb[ids[i]] += repayLb;
            _totalSupplies[ids[i]] -= tokenAmount[i];

            if (_borrowedLb[to][ids[i]] == 0) {
                _borrowedIds[to].remove(ids[i]);
            }
            usdjToTransfer += amounts[i];
        }

        USDJ.transferFrom(to, address(this), usdjToTransfer);
        _update(to, address(0), ids, tokenAmount);
        require(_getHealthFactorMantissa(to) >= BASE_HEALTH_FACTOR, "health factor too low");
    }

    /**
     * @notice Liquidate a user's position
     * @param user The user to liquidate
     * @param ids The ids of Collateral LBPair Tokens
     * @param amounts The amounts of the USDJ to repay
     */
    function liquidate(address user, uint256[] memory ids, uint256[] memory amounts) external nonReentrant {
        _liquidate(msg.sender, user, ids, amounts);
    }

    function _liquidate(address liquidator, address user, uint256[] memory ids, uint256[] memory amounts) internal {
        require(ids.length == amounts.length, "invalid liquidate param length");
        require(_getHealthFactorMantissa(user) < BASE_HEALTH_FACTOR, "user is not underwater");

        uint256 usdjToTransfer = 0;
        uint256[] memory tokenAmount = new uint256[](ids.length);
        for (uint256 i; i < ids.length; i++) {
            require(amounts[i] <= _borrowedUsdj[user][ids[i]], "amounts[i] is too large");
            _accrueInterest(ids[i]);
            _incurInterest(user, ids[i]);

            uint256 repayLb = _borrowedLb[user][ids[i]] * amounts[i] / _borrowedUsdj[user][ids[i]];
            uint256 interestLb = _accruedInterest[user][ids[i]] * amounts[i] / _borrowedUsdj[user][ids[i]];
            tokenAmount[i] = (interestLb + repayLb) * _expScale / _getExchangeRateMantissa(ids[i]);

            _accruedInterest[user][ids[i]] -= interestLb;
            _borrowedLb[user][ids[i]] -= repayLb;
            _borrowedUsdj[user][ids[i]] -= amounts[i];
            _totalBorrowedLb[ids[i]] -= repayLb;
            _totalBorrowedUsdj[ids[i]] -= amounts[i];
            _totalLb[ids[i]] += repayLb;

            _collateralIds[liquidator].add(ids[i]);
            if (_borrowedLb[user][ids[i]] == 0) {
                _borrowedIds[user].remove(ids[i]);
            }
            usdjToTransfer += amounts[i];
        }

        require(_getHealthFactorMantissa(user) >= BASE_HEALTH_FACTOR, "health factor too low");
        USDJ.transferFrom(liquidator, address(this), usdjToTransfer);
        _update(user, liquidator, ids, tokenAmount);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactorMantissa(user);
    }

    function _getHealthFactorMantissa(address user) internal view returns (uint256) {
        uint256 userCollateralWorthMantissa = 0;
        uint256 userBorrowWorthMantissa = 0;

        for (uint256 i; i < _borrowedIds[user].length(); i++) {
            uint256 id = _borrowedIds[user].at(i);
            userBorrowWorthMantissa += getAssetPrice(USDJ) * _borrowedUsdj[user][id];
        }
        for (uint256 i; i < _collateralIds[user].length(); i++) {
            uint256 id = _collateralIds[user].at(i);

            userCollateralWorthMantissa += (
                _getLiquidityValueMantissa(id, _lbPair.totalSupply(id)) / _lbPair.totalSupply(id)
                    * _getExchangeRateMantissa(id) * balanceOf(user, id) / _expScale
            ) - _getLiquidityValueMantissa(id, _accruedInterest[user][id]);
        }

        if (userBorrowWorthMantissa == 0) {
            return type(uint256).max;
        }

        return userCollateralWorthMantissa * _expScale / userBorrowWorthMantissa;
    }

    function hypotheticalHealthCheck(
        address user,
        uint256[] memory ids,
        uint256[] memory amounts,
        RedeemOrborrow redeemOrborrow
    ) internal returns (uint256, uint256) {
        uint256 sumCollateral = 0;
        uint256 sumBorrowPlusEffects = 0;

        for (uint256 i; i < _borrowedIds[user].length(); i++) {
            uint256 id = _borrowedIds[user].at(i);
            sumBorrowPlusEffects += getAssetPrice(USDJ) * _borrowedUsdj[user][id];
        }
        if (redeemOrborrow == RedeemOrborrow.BORROW) {
            for (uint256 i; i < ids.length; i++) {
                uint256 id = ids[i];
                sumBorrowPlusEffects += getAssetPrice(USDJ) * amounts[i];
                sumBorrowPlusEffects += _getLiquidityValueMantissa(id, _accruedInterest[user][id]);
            }
        }

        for (uint256 i; i < _collateralIds[user].length(); i++) {
            uint256 id = _collateralIds[user].at(i);
            sumCollateral += (
                _getLiquidityValueMantissa(id, _lbPair.totalSupply(id)) / _lbPair.totalSupply(id)
                    * _getExchangeRateMantissa(id) * balanceOf(user, id) / _expScale
            );
            sumCollateral = sumCollateral * COLLATERAL_FACTOR / _expScale;
        }
        if (redeemOrborrow == RedeemOrborrow.REDEEM) {
            for (uint256 i; i < ids.length; i++) {
                uint256 id = ids[i];
                sumBorrowPlusEffects += (
                    _getLiquidityValueMantissa(id, _lbPair.totalSupply(id)) / _lbPair.totalSupply(id)
                        * _getExchangeRateMantissa(id) * amounts[i] / _expScale
                ) * COLLATERAL_FACTOR / _expScale;
            }
        }

        if (sumCollateral > sumBorrowPlusEffects) {
            return (sumCollateral - sumBorrowPlusEffects, 0);
        } else {
            return (0, sumBorrowPlusEffects - sumCollateral);
        }
    }

    function sync(address user, uint256 id) external nonReentrant {
        _accrueInterest(id);
        _incurInterest(user, id);
    }

    function _accrueInterest(uint256 id) internal {
        if (block.timestamp > _totalAccrualTimestamp[id]) {
            uint256 interestAccrued = (((_totalBorrowedLb[id] * INTEREST_RATE) / _expScale) / 365 days)
                * (block.timestamp - _totalAccrualTimestamp[id]);
            _totalBorrowedLb[id] += interestAccrued;
            _totalAccrualTimestamp[id] = block.timestamp;
        }
    }

    function _incurInterest(address from, uint256 id) internal {
        if (block.timestamp > _accrualTimestamp[from][id]) {
            _accruedInterest[from][id] += (((_borrowedLb[from][id] * INTEREST_RATE) / _expScale) / 365 days)
                * (block.timestamp - _accrualTimestamp[from][id]);
            _accrualTimestamp[from][id] = block.timestamp;
        }
    }

    function getExchangeRate(uint256 id) public view returns (uint256) {
        return _getExchangeRateMantissa(id) / _expScale;
    }

    function _getExchangeRateMantissa(uint256 id) internal view returns (uint256) {
        uint256 totalSupply = _totalSupplies[id];

        if (totalSupply == 0) {
            return _initialExchangeRate;
        } else {
            uint256 exchangeRateMantissa = (_totalLb[id] + _totalBorrowedLb[id]) * _expScale / totalSupply;
            return exchangeRateMantissa == 0 ? _initialExchangeRate : exchangeRateMantissa;
        }
    }

    function _getLiquidityValueMantissa(uint256 id, uint256 amount)
        internal
        view
        returns (uint256 reserveWorthMantissa)
    {
        (uint128 x, uint128 y) = _lbPair.getBin(uint24(id));
        bytes32 reserve = x.encode(y);
        reserve = BinHelper.getAmountOutOfBin(reserve, amount, _lbPair.totalSupply(id));
        (x, y) = reserve.decode();
        reserveWorthMantissa =
            ((x * getAssetPrice(getTokenX()) * (10 ** _xOffset)) + (y * getAssetPrice(getTokenY()) * (10 ** _yOffset)));
    }

    function getLiquidityValue(uint256 id, uint256 amount) public view returns (uint256) {
        return _getLiquidityValueMantissa(id, amount) / _expScale;
    }

    function getUserBorrowableAmount(address user, uint256 id) public view returns (uint256) {
        uint256 userBorrowedTotalWorthMantissa = getAssetPrice(USDJ) * _borrowedUsdj[user][id];
        uint256 reserveWorthMantissa = _getLiquidityValueMantissa(id, _lbPair.totalSupply(id)) / _lbPair.totalSupply(id)
            * _getExchangeRateMantissa(id) * balanceOf(user, id) / _expScale;
        return (reserveWorthMantissa / BASE_HEALTH_FACTOR) - (userBorrowedTotalWorthMantissa / _expScale);
    }

    function getUserBorrowedAmount(address user, uint256 id) public view returns (uint256) {
        return _borrowedUsdj[user][id];
    }

    function getUserCollateralValue(address user, uint256 id) public view returns (uint256) {
        return
            _getLiquidityValueMantissa(id, (balanceOf(user, id) * _getExchangeRateMantissa(id) / _expScale)) / _expScale;
    }

    function getUserLbBalance(address user, uint256 id) public view returns (uint256) {
        return (balanceOf(user, id) * _getExchangeRateMantissa(id) / _expScale);
    }

    function getUserBorrowedLb(address user, uint256 id) public view returns (uint256) {
        return _borrowedLb[user][id];
    }

    function getUserBorrowedUsdj(address user, uint256 id) public view returns (uint256) {
        return _borrowedUsdj[user][id];
    }

    function setAssetOracle(IERC20 asset, address oracle) public onlyOwner {
        if (_priceOracles[asset] == address(0)) {
            _priceOracles[asset] = oracle;
        }
    }

    function getAssetPrice(IERC20 asset) public view returns (uint256) {
        return IPriceOracle(_priceOracles[asset]).latestAnswer() * 1e10;
    }

    function getTokenX() public view returns (IERC20) {
        return _lbPair.getTokenX();
    }

    function getTokenY() public view returns (IERC20) {
        return _lbPair.getTokenY();
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        super._update(from, to, ids, values);
        if (from != address(0) && _reentrancyGuardEntered() != true) {
            require(_getHealthFactorMantissa(from) >= BASE_HEALTH_FACTOR, "health factor too low");
        }
    }
}

contract MintableERC20 is ERC20 {
    uint8 public decimalsInternal;

    function decimals() public view override returns (uint8) {
        return decimalsInternal;
    }

    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        _mint(msg.sender, type(uint256).max);
        decimalsInternal = _decimals;
    }
}

interface IPriceOracle {
    function latestAnswer() external view returns (uint256);
}
