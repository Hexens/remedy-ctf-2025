// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { IStaderOracle } from "src/tokemak/interfaces/external/stader/IStaderOracle.sol";

interface IStaderConfig {
    function getStaderOracle() external view returns (IStaderOracle);
}
