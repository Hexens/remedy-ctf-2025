// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/AdminNFT.sol";
import "src/Bridge.sol";

contract Challenge {
    address public immutable PLAYER;
    AdminNFT public immutable ADMIN_NFT;
    Bridge public immutable BRIDGE;

    bool public stage1Solved = false;
    bool public stage2Solved = false;
    bool public stage3Solved = false;

    bool public challengeSolved = false;
    address public solver;

    event StageSolved(uint256 stage, address solver);
    event ChallengeSolved(address solver);
    
    int256 private constant A = 3;
    int256 private constant B = -5;
    int256 private constant C = 2;
    int256 private constant D = -7;

    uint256 private constant MODULUS = 101;
    uint256 private constant TARGET_1 = 36;
    uint256 private constant PRODUCT = 5959;

    constructor(address player) payable {
        PLAYER = player;
        address[] memory withdrawValidators = new address[](1);
        withdrawValidators[0] = msg.sender;
        BRIDGE = new Bridge{value: 100 ether}(address(this), 10, withdrawValidators);
        ADMIN_NFT = AdminNFT(BRIDGE.adminNftContract());
    }

    function solveStage1(uint256 x) external {
        require(!stage1Solved, "Stage 1 already solved");

        uint256 result = (x * x) % MODULUS;

        require(result == TARGET_1, "Incorrect solution for Stage 1");

        stage1Solved = true;
        emit StageSolved(1, msg.sender);
    }

    function solveStage2(uint256 a, uint256 b) external {
        require(!stage2Solved, "Stage 2 already solved");

        require(a * b == PRODUCT, "Incorrect solution for Stage 2");

        stage2Solved = true;
        emit StageSolved(2, msg.sender);
    }

    function solveStage3(uint256 x, uint256 y, uint256 z) external {
        require(!stage3Solved, "Stage 3 already solved");

        int256 result = A * int256(x**3) + B * int256(y**2) + C * int256(z) + D;

        require(result == 0, "Incorrect solution for Stage 3");

        stage3Solved = true;
        emit StageSolved(3, msg.sender);
    }

    function solveStage3(uint128 x, uint128 y) external {
        require(!stage3Solved, "Stage 3 already solved");
       
        int256 result = A * int256(uint256(x))**3 + B * int256(uint256(y))**2 + C * int256(128) + D;
        require(result == 0, "Incorrect solution for Stage 3");
        stage3Solved = true;
        emit StageSolved(3, msg.sender);
    }

    function completeChallenge(address _solver) external {
        require(msg.sender == address(BRIDGE), "Not Bridge");
        require(!challengeSolved, "Challenge already completed");

        challengeSolved = true;
        solver = _solver;
        emit ChallengeSolved(_solver);
    }

    function getChallengeStatus() external view returns (bool, bool, bool) {
        return (stage1Solved, stage2Solved, stage3Solved);
    }

    function isSolved() external view returns (bool) {
        return challengeSolved 
            && solver == PLAYER 
            && address(BRIDGE).balance == 0;
    }
}