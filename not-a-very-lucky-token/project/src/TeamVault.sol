pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LuckyToken.sol";
import "./LockStaking.sol";

contract TeamVault is Ownable {

    LuckyToken public token;
    address public team;
    LockStaking public lockStaking;

    event Released(address lockStaking, uint256 amount);
    event Withdrawn(address owner, uint256 amount);

    constructor(address _team) {
        token = LuckyToken(msg.sender);
        team = _team;
    }

    function setToken(address _token, address _team) external onlyOwner {}

    function release() external {
        require(token.txCount() > 10, "TeamVault: not ready");
        lockStaking = new LockStaking{salt: getSalt()}(
            address(token),
            12
        );
        token.addSpecialReceiver(address(lockStaking), true);
        token.approve(address(lockStaking), token.balanceOf(address(this)));
        lockStaking.deposit(token.balanceOf(address(this)));
        emit Released(msg.sender, 12);
    }

    function getSalt() internal view returns (bytes32) {
        return bytes32(uint256(uint160(msg.sender)));
    }
    
    function withdraw() external onlyOwner {
        require(block.timestamp > 1737964800);
        token.transfer(team, token.balanceOf(address(this)));
        emit Withdrawn(msg.sender, token.balanceOf(address(this)));
    }
}
