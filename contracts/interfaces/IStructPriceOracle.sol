// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

/**
 * @title The StructPriceOracle interface
 * @notice Interface for the Struct price oracle.
 *
 */
interface IStructPriceOracle {
    ///@dev returns the asset price in USD
    ///@param asset the address of the asset
    ///@return the USD price of the asset
    function getAssetPrice(address asset) external view returns (uint256);

    ///@dev returns the asset prices in USD
    ///@param assets the addresses array of the assets
    ///@return the USD prices of the asset
    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory);
}
