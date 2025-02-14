// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "src/tokemak/SystemRegistry.sol";
import "src/tokemak/vault/AutopilotRouter.sol";
import "src/tokemak/vault/AutopoolETH.sol";
import "src/tokemak/interfaces/utils/IWETH9.sol";

contract LFGStaker is ERC20 {

    IWETH9              public immutable weth;
    SystemRegistry      public immutable system;
    AutopoolETH         public immutable autoETH;
    IAutopilotRouter    public immutable router;

    constructor(SystemRegistry _system, AutopoolETH _autoETH) ERC20("LFG Staker", "LFGS") {
        autoETH = _autoETH;
        system = _system;
        weth = system.weth();
        router = system.autoPoolRouter();
        weth.approve(address(router), type(uint).max);
        autoETH.approve(address(router), type(uint).max);
    }

    function deposit(uint amount) external {
        uint assets = autoETH.convertToAssets(amount);
        uint shares = convertToShares(assets, false);
        
        _mint(msg.sender, shares);

        autoETH.transferFrom(msg.sender, address(this), amount);
    }

    function mint(uint shares) external {
        uint assets = convertToAssets(shares, true);
        uint amount = autoETH.convertToShares(assets);
        
        _mint(msg.sender, shares);

        autoETH.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) external {
        uint assets = autoETH.convertToAssets(amount);
        uint shares = convertToShares(assets, true);
        
        _burn(msg.sender, shares);

        autoETH.transfer(msg.sender, amount);
    }

    function redeem(uint shares) external {
        uint assets = convertToAssets(shares, false);
        uint amount = autoETH.convertToShares(assets);
        
        _burn(msg.sender, shares);

        autoETH.transfer(msg.sender, amount);
    }

    function convertToAssets(uint shares, bool up) public returns (uint) {
        uint totalAssets = totalAssets();
        uint totalSupply = totalSupply();
        if (totalSupply == 0)
            return shares;
        return ((shares * totalAssets) + (up ? totalSupply - 1 : 0)) / totalSupply;
    }

    function convertToShares(uint assets, bool up) public returns (uint) {
        uint totalAssets = totalAssets();
        uint totalSupply = totalSupply();
        if (totalAssets == 0)
            return assets;
        return ((assets * totalSupply) + (up ? totalAssets - 1 : 0)) / totalAssets;
    }

    function totalAssets() public returns (uint) {
        return autoETH.previewRedeem(autoETH.balanceOf(address(this)));
    }
}