pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./TeamVault.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Factory.sol";

contract LuckyToken is ERC20("LuckyToken", "LTN"), AccessControl {

    uint256 public constant ICE = 5;
    uint256 public constant FIRE = 10;

    uint256 public totalAmountMinted;
    uint256 public totalAmountBurned;

    mapping(address => bool) public specialSender;
    mapping(address => bool) public specialReceiver;

    uint256 public nonce;
    uint256 public txCount;
    TeamVault public teamVault;
    address public liquidityProvider;
    bool public tradingOpen;
    address public uniswapV2Pair;

    bytes32 public constant ADD_ROLE = keccak256("ADD_ROLE");

    IUniswapV2Router01 internal constant UNISWAPV2_ROUTER =
        IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    event Ice(address indexed sender, uint256 amount);
    event Fire(address indexed sender, uint256 amount);

    event AddSpecialReceiver(address indexed receiver, bool status);
    event AddSpecialSender(address indexed sender, bool status);

    constructor(uint256 _nonce, address _team) payable {
        nonce = _nonce;
        teamVault = new TeamVault(_team);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADD_ROLE, address(teamVault));
        _setupRole(ADD_ROLE, msg.sender);

        _addSpecialSender(address(this), true);

        _mint(address(teamVault), 1000000 * 10 ** decimals());
        _mint(address(this), 10 * 10 ** decimals());

        _approve(address(this), address(UNISWAPV2_ROUTER), type(uint256).max);
    }

    function addSpecialReceiver(address _user, bool _bypass) public {
        require(
            hasRole(ADD_ROLE, msg.sender),
            "Caller doesn't have permission"
        );
        _addSpecialReceiver(_user, _bypass);
    }

    function _addSpecialReceiver(address _user, bool _bypass) private {
        if (balanceOf(_user) == 0) {
            specialReceiver[_user] = _bypass;
        }
        emit AddSpecialReceiver(_user, specialReceiver[_user]);
    }

    function addSpecialSender(address _user, bool _bypass) public {
        require(
            hasRole(ADD_ROLE, msg.sender),
            "Caller doesn't have permission"
        );
        _addSpecialSender(_user, _bypass);
    }

    function _addSpecialSender(address _user, bool _bypass) internal {
        if (balanceOf(_user) == 0) {
            specialSender[_user] = _bypass;
        }
        emit AddSpecialSender(_user, specialSender[_user]);
    }

    function _calculateNonce(
        address _s1,
        address _s2,
        uint256 _s3,
        uint256 _s4,
        uint256 _s5,
        bytes32 _s6
    ) public pure returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(_s1, _s2, _s3, _s4, _s5, _s6))
            );
    }
    
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal virtual override {
        if (specialReceiver[_recipient]) {
            super._transfer(_sender, _recipient, _amount);
            return;
        }
        if (!specialSender[_sender]) {
            nonce = _calculateNonce(
                msg.sender,
                _recipient,
                block.timestamp,
                _amount,
                nonce,
                blockhash(block.number - 1)
            );

            bool status = ((nonce % 101) & 1) == 0;
            uint256 pendingAmount = (_amount * (status ? ICE : FIRE)) / 100;
            if (status) {
                if (totalAmountMinted + pendingAmount < totalAmountBurned) {
                    super._mint(_sender, pendingAmount);
                    totalAmountMinted += pendingAmount;
                    emit Ice(_sender, pendingAmount);
                }
            } else {
                super._burn(_sender, pendingAmount);
                totalAmountBurned += pendingAmount;
                _amount -= pendingAmount;
                emit Fire(_sender, pendingAmount);
            }
            txCount += 1;
            _amount -= 1;
        }

        super._transfer(_sender, _recipient, _amount);
    }

    function openTrading() public {
        require(!tradingOpen, "trading is already open");
        require(
            hasRole(ADD_ROLE, msg.sender),
            "Caller doesn't have permission"
        );
        tradingOpen = true;
        uniswapV2Pair = IUniswapV2Factory(UNISWAPV2_ROUTER.factory())
            .createPair(address(this), UNISWAPV2_ROUTER.WETH());
        _addSpecialSender(uniswapV2Pair, true);
        _addSpecialSender(address(UNISWAPV2_ROUTER), true);

        UNISWAPV2_ROUTER.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            msg.sender,
            block.timestamp
        );
        _burn(address(this), balanceOf(address(this)));
    }
}
