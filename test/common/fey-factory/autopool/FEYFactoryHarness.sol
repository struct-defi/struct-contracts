// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@core/products/autopool/FEYAutoPoolProductFactory.sol";

contract FEYFactoryHarness is FEYAutoPoolProductFactory {
    constructor(
        ISPToken _spTokenAddress,
        address _feyProductImpl,
        IGAC _globalAccessControl,
        IStructPriceOracle _priceOracle,
        IERC20Metadata _wAVAX,
        IDistributionManager _distributionManager
    )
        FEYAutoPoolProductFactory(
            _spTokenAddress,
            _feyProductImpl,
            _globalAccessControl,
            _priceOracle,
            _wAVAX,
            _distributionManager
        )
    {}

    function getFirstProduct() external view returns (address) {
        return allProducts[0];
    }
}
