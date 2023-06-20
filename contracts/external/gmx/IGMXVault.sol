// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

interface IGMXVault {
    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);

    function mintBurnFeeBasisPoints() external view returns (uint256);

    function taxBasisPoints() external view returns (uint256);

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function whitelistedTokens(address _token) external view returns (bool);
}
