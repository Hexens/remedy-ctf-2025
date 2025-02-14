// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IL2Coordinator } from "src/tokemak/interfaces/external/aura/IL2Coordinator.sol";

interface IBoosterLite {
    function minter() external view returns (IL2Coordinator);
}
