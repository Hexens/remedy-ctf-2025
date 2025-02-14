// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./VaultFactory.sol";
import "./Vault.sol";
import "./Diamond.sol";
import "./HexensCoin.sol";

contract Challenge {
    address public immutable PLAYER;

    uint constant public DIAMONDS = 31337;
    uint constant public HEXENS_COINS = 10_000 ether;
    bool claimed;

    VaultFactory public vaultFactory;
    Vault public vault;
    Diamond public diamond;
    HexensCoin public hexensCoin;

    constructor (address player) {
        PLAYER = player;
        vaultFactory = new VaultFactory();
        vault = vaultFactory.createVault(keccak256("The tea in Nepal is very hot. But the coffee in Peru is much hotter."));
        diamond = new Diamond(DIAMONDS);
        hexensCoin = new HexensCoin();
        vault.initialize(address(diamond), address(hexensCoin));
        diamond.transfer(address(vault), DIAMONDS);
    }

    function claim() external {
        require(!claimed);
        claimed = true;
        hexensCoin.mint(msg.sender, HEXENS_COINS);
    }

    function isSolved() external view returns (bool) {
        return diamond.balanceOf(PLAYER) == DIAMONDS;
    }
}