// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

contract MockOracle {
    mapping(address => uint256) prices;

    function setAssetPrice(address _asset, uint256 _price) external {
        prices[_asset] = _price;
    }

    function getAssetPrice(address _asset) external view returns (uint256) {
        return prices[_asset];
    }
}
