// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IFEYProduct.sol";
import "@interfaces/IStructPriceOracle.sol";
import "@core/libraries/types/DataTypes.sol";

interface IFEYProductHarness is IFEYProduct {
    function tokenDecimals() external view returns (uint256 _srDecimals, uint256 _jrDecimals);

    function productConfig() external view returns (DataTypes.ProductConfig memory productConfig);

    function srFrFactor_exposed(uint256 _fixedRate, uint256 _durationInSeconds, uint256 _tokensInvestable)
        external
        view
        returns (uint256 _srFrFactor);
}
