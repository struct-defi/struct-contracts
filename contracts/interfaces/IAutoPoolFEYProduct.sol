// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import {IFEYProduct} from "./IFEYProduct.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {IAutoPoolYieldSource} from "./IAutoPoolYieldSource.sol";

interface IAutoPoolFEYProduct is IFEYProduct {
    function processRedemption(uint256, uint256) external;
    function getTokenRate(DataTypes.Tranche _tranche, uint256 _amountOut)
        external
        view
        returns (bool, uint256, uint256, uint256);
    function yieldSource() external view returns (IAutoPoolYieldSource);
    function getSrFrFactor(bool _isProrated) external view returns (uint256 _srFrFactor);
}
