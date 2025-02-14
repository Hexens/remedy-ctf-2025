// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";

import { IRateProvider } from "src/tokemak/interfaces/external/balancer/IRateProvider.sol";

/**
 * @title ERC4626 Rate Provider
 * @notice Returns an 18 decimal fixed point number that is the exchange rate of the
 * shares of an ERC4626 to the underlying asset
 */
contract ERC4626RateProvider is IRateProvider {
    IERC4626 public immutable erc4626;
    uint256 public immutable fixedPointOne;

    constructor(
        IERC4626 _erc4626
    ) {
        erc4626 = _erc4626;
        uint256 underlyingDecimals = IERC4626(_erc4626.asset()).decimals();
        // Balancer does not support tokens with more than 18 decimals so this will never underflow
        fixedPointOne = 10 ** (18 + _erc4626.decimals() - underlyingDecimals);
    }

    /**
     * @return An 18 decimal fixed point number that is the exchange rate of the
     * shares of an ERC4626 to the underlying asset
     */
    function getRate() external view override returns (uint256) {
        return erc4626.convertToAssets(fixedPointOne);
    }
}
