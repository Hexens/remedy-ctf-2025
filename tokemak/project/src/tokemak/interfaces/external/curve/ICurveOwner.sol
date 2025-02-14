// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase, var-name-mixedcase
// slither-disable-start naming-convention
interface ICurveOwner {
    function withdraw_admin_fees(
        address _pool
    ) external;
}
// slither-disable-end naming-convention
