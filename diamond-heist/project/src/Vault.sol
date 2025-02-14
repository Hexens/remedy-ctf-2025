// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./openzeppelin-contracts/interfaces/IERC20.sol";
import "./openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import "./openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "./openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Diamond.sol";
import "./Burner.sol";
import "./HexensCoin.sol";

contract Vault is Initializable, UUPSUpgradeable, OwnableUpgradeable {

    uint constant public AUTHORITY_THRESHOLD = 100_000 ether;

    Diamond diamond;
    HexensCoin hexensCoin;

    function initialize(address diamond_, address hexensCoin_) public initializer {
        __Ownable_init();
        diamond = Diamond(diamond_);
        hexensCoin = HexensCoin(hexensCoin_);
    }

    function governanceCall(bytes calldata data) external {
        require(msg.sender == owner() || hexensCoin.getCurrentVotes(msg.sender) >= AUTHORITY_THRESHOLD);
        (bool success,) = address(this).call(data);
        require(success);
    }

    function burn(address token, uint amount) external {
        require(msg.sender == owner() || msg.sender == address(this));
        Burner burner = new Burner();
        IERC20(token).transfer(address(burner), amount);
        burner.destruct();
    }
    
    function _authorizeUpgrade(address) internal override view {
        require(msg.sender == owner() || msg.sender == address(this));
        require(IERC20(diamond).balanceOf(address(this)) == 0);
    }
}
