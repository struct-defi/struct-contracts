pragma solidity 0.8.11;

import "@core/yield-sources/GMXYieldSource.sol";
import "@mocks/MockERC20.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";
import "@interfaces/IGMXYieldSource.sol";
import "@interfaces/IGAC.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

contract GMXYieldSourceHarness is GMXYieldSource {
    constructor(address _feyFactory, address _gac) GMXYieldSource(_feyFactory, IGAC(_gac)) {}

    function populateProductInfo(
        address _productAddress,
        address _tokenA,
        address _tokenB,
        uint8 _tokenADecimals,
        uint8 _tokenBDecimals
    ) external {
        DataTypes.FEYGMXProductInfo memory _productInfo = DataTypes.FEYGMXProductInfo({
            tokenA: _tokenA,
            tokenB: _tokenB,
            tokenADecimals: _tokenADecimals,
            tokenBDecimals: _tokenBDecimals,
            fsGLPReceived: 0,
            shares: 0,
            sameToken: _tokenA == _tokenB
        });

        productInfo[_productAddress] = _productInfo;
    }

    function tokenToShares(uint256 _amount, uint256 _lpTotal) external view returns (uint256 _shares) {
        _shares = _tokenToShares(_amount, _lpTotal);
    }

    function sharesToTokens(uint256 _shares, uint256 _lpTotal) external view returns (uint256 _tokens) {
        _tokens = _sharesToTokens(_shares, _lpTotal);
    }

    function setTotalShares(uint256 _amount) external {
        totalShares = _amount;
    }

    function getTotalShares() external view returns (uint128) {
        return uint128(totalShares);
    }

    function getfsGlpTokensTotal() external view returns (uint256) {
        return fsGlpTokensTotal;
    }

    function getFsGlpPrice(bool _maximize) external view returns (uint256) {
        return _getGLPPrice(_maximize);
    }
}
