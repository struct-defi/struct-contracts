// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IStructPriceOracle.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IStructPriceOracleHarness is IStructPriceOracle {
    function setAssetSources(address[] calldata assets, AggregatorV3Interface[] calldata sources) external;
}
