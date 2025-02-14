// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { ILRTConfig } from "src/tokemak/interfaces/external/kelpdao/ILRTConfig.sol";

interface IRSETH {
    /// @notice Returns an instance of the LRTConfig contract
    function lrtConfig() external view returns (ILRTConfig);
}
