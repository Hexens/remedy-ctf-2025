// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-ctf/CTFDeployer.sol";

import "src/Challenge.sol";

contract Deploy is CTFDeployer {

    address constant TOKEMAK_TREASURY = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;

    function deploy(address system, address player) internal override returns (address challenge) {
        vm.startBroadcast(system);

        challenge = address(new Challenge(player));
        AutopoolETH autoETH = AutopoolETH(Challenge(challenge).AUTOPOOL_ETH());
        LFGStaker staker = LFGStaker(Challenge(challenge).LFG_STAKER());

        vm.stopBroadcast();

        // Fund System with 100 autoETH from Tokemak treasury
        vm.startBroadcast(TOKEMAK_TREASURY);
        autoETH.transfer(system, 100 ether);
        vm.stopBroadcast();

        vm.startBroadcast(system);

        autoETH.approve(address(staker), type(uint).max);
        staker.deposit(100 ether);

        vm.stopBroadcast();
    }
}
