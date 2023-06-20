// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./IStructPriceOracleHarness.sol";

/**
 * @title Struct Price Oracle User contract
 * @notice User contract to interact with Struct Price Oracle Contract.
 *
 */
contract PriceOracleUser is ERC1155Holder {
    IStructPriceOracleHarness public priceOracle;

    constructor(address _priceOracle) {
        priceOracle = IStructPriceOracleHarness(_priceOracle);
    }

    function setAssetSources(address[] calldata assets, AggregatorV3Interface[] calldata sources) external {
        priceOracle.setAssetSources(assets, sources);
    }
}
