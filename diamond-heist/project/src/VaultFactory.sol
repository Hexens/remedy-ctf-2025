// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Vault.sol";

contract VaultFactory {

    address vaultImpl;

    constructor() {
        vaultImpl = address(new Vault());
    }

    function createVault(bytes32 salt_) external returns (Vault) {
        return Vault(address(new ERC1967Proxy{salt: salt_}(vaultImpl, "")));
    }
}