// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// solhint-disable func-name-mixedcase
interface IVoter {
    error GaugeNotAlive(address _gauge);

    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external;

    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external;

    // mapping(address => address) public gauges; // pool => gauge
    function gauges(
        address pool
    ) external view returns (address);

    // mapping(address => address) public poolForGauge; // gauge => pool
    function poolForGauge(
        address gauge
    ) external view returns (address);

    // mapping(address => address) public internal_bribes; // gauge => internal bribe (only fees)
    // solhint-disable-next-line func-name-mixedcase
    function internal_bribes(
        address gauge
    ) external view returns (address);

    // mapping(address => address) public external_bribes; // gauge => external bribe (real bribes)
    function external_bribes(
        address gauge
    ) external view returns (address);

    // Checks gauge status
    function isAlive(
        address gauge
    ) external view returns (bool);
}
