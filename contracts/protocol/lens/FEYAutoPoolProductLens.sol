// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Constants} from "../libraries/helpers/Constants.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

import {IAutoPoolFEYProduct} from "../../interfaces/IAutoPoolFEYProduct.sol";
import {IAutoPoolYieldSource} from "../../interfaces/IAutoPoolYieldSource.sol";
import {IAutoPoolVault} from "../../external/traderjoe/IAutoPoolVault.sol";
import {WadMath} from "../../utils/WadMath.sol";

/**
 * @title FEYAutoPoolProduct Lens contract
 * @notice Exposes getter methods to query AutoPoolProduct related data
 * @author Struct Finance
 */

contract FEYAutoPoolProductLens {
    using WadMath for uint256;

    /**
     * @notice calculates the amount of tranche tokens that the market would receive
     * @param _yieldSource the yield source address
     * @return _expectedTrancheTokensA the amount of A tokens to receive
     * @return _expectedTrancheTokensB the amount of B tokens to receive
     * @return _tokenA the address of the A token
     * @return _tokenB the address of the B token
     */
    function getMarketTokensReceived(IAutoPoolYieldSource _yieldSource)
        external
        view
        returns (uint256 _expectedTrancheTokensA, uint256 _expectedTrancheTokensB, address _tokenA, address _tokenB)
    {
        uint256 _autoPoolShareTokensWAD = _yieldSource.totalAutoPoolShareTokens();
        (_expectedTrancheTokensA, _expectedTrancheTokensB) =
            _getTokensReceived(_autoPoolShareTokensWAD, address(_yieldSource.tokenA()), _yieldSource);
        return (
            _expectedTrancheTokensA,
            _expectedTrancheTokensB,
            address(_yieldSource.tokenA()),
            address(_yieldSource.tokenB())
        );
    }

    /**
     * @notice Preview the amount of tokens to allocate to the tranches
     * @param _product Product to preview allocation for
     * @return _expectedTrancheTokensSr Amount of senior tokens received after allocation
     * @return _expectedTrancheTokensJr Amount of junior tokens received after allocation
     */
    function previewAllocateToTranches(IAutoPoolFEYProduct _product)
        public
        view
        returns (uint256 _expectedTrancheTokensSr, uint256 _expectedTrancheTokensJr)
    {
        if (_product.getCurrentState() != DataTypes.State.INVESTED) return (0, 0);
        (bool _isPriceValidSr, uint256 _jrToSrRate,,) = _product.getTokenRate(DataTypes.Tranche.Senior, 0);
        require(_isPriceValidSr, Errors.PFE_INVALID_SR_PRICE);

        (bool _isPriceValidJr, uint256 _srToJrRate,,) = _product.getTokenRate(DataTypes.Tranche.Junior, 0);
        require(_isPriceValidJr, Errors.PFE_INVALID_JR_PRICE);

        DataTypes.TrancheConfig memory trancheConfigSr = _product.getTrancheConfig(DataTypes.Tranche.Senior);
        (_expectedTrancheTokensSr, _expectedTrancheTokensJr) =
            _getProductTokensReceived(_product, address(trancheConfigSr.tokenAddress));

        uint256 _srFrFactorProRata = _product.getSrFrFactor(true);
        if (_srFrFactorProRata > _expectedTrancheTokensSr + _expectedTrancheTokensJr.wadMul(_srToJrRate)) {
            _expectedTrancheTokensSr += _expectedTrancheTokensJr.wadMul(_srToJrRate);
            _expectedTrancheTokensJr = 0;
        } else if (_srFrFactorProRata < _expectedTrancheTokensSr) {
            uint256 _amountToSwap = _expectedTrancheTokensSr - _srFrFactorProRata;
            _expectedTrancheTokensSr -= _amountToSwap;
            _expectedTrancheTokensJr += _amountToSwap.wadDiv(_srToJrRate);
        } else if (_srFrFactorProRata > _expectedTrancheTokensSr) {
            uint256 _amountOut = _srFrFactorProRata - _expectedTrancheTokensSr;
            _expectedTrancheTokensJr -= _amountOut.wadMul(_jrToSrRate);
            _expectedTrancheTokensSr += _amountOut;
        }
    }

    /**
     * @notice calculates the amount of tranche tokens that the product would receive
     * @param _product the product address
     * @param _tokenSr the senior token address
     * @return _expectedTrancheTokensSr the amount of senior tokens to receive
     * @return _expectedTrancheTokensJr the amount of junior tokens to receive
     */
    function _getProductTokensReceived(IAutoPoolFEYProduct _product, address _tokenSr)
        private
        view
        returns (uint256 _expectedTrancheTokensSr, uint256 _expectedTrancheTokensJr)
    {
        IAutoPoolYieldSource _yieldSource = _product.yieldSource();
        uint256 _productStructShares = _yieldSource.productAPTShare(address(_product));
        uint256 _productApTokenShares = _yieldSource.sharesToTokens(
            _productStructShares, _yieldSource.totalShares(), _yieldSource.totalAutoPoolShareTokens()
        );
        return _getTokensReceived(_productApTokenShares, _tokenSr, _yieldSource);
    }

    /**
     * @notice preview the amount of tokens received upon share redemption
     * @param _shares the amount of shares to redeem
     * @param _tokenSr the senior token address
     * @param _yieldSource the yield source address
     * @return _expectedTrancheTokensSr the amount of senior tokens to receive
     * @return _expectedTrancheTokensJr the amount of junior tokens to receive
     */
    function _getTokensReceived(uint256 _shares, address _tokenSr, IAutoPoolYieldSource _yieldSource)
        private
        view
        returns (uint256 _expectedTrancheTokensSr, uint256 _expectedTrancheTokensJr)
    {
        IAutoPoolVault _autoPoolVault = _yieldSource.autoPoolVault();
        (uint256 _receivedA, uint256 _receivedB) = _autoPoolVault.previewAmounts(_shares);

        if (_tokenSr == address(_yieldSource.tokenA())) {
            (_expectedTrancheTokensSr, _expectedTrancheTokensJr) = (_receivedA, _receivedB);
            _expectedTrancheTokensSr = tokenDecimalsToWei(_yieldSource.tokenA().decimals(), _expectedTrancheTokensSr);
            _expectedTrancheTokensJr = tokenDecimalsToWei(_yieldSource.tokenB().decimals(), _expectedTrancheTokensJr);
        } else {
            (_expectedTrancheTokensSr, _expectedTrancheTokensJr) = (_receivedB, _receivedA);
            _expectedTrancheTokensSr = tokenDecimalsToWei(_yieldSource.tokenB().decimals(), _expectedTrancheTokensSr);
            _expectedTrancheTokensJr = tokenDecimalsToWei(_yieldSource.tokenA().decimals(), _expectedTrancheTokensJr);
        }
    }

    /**
     * @notice Converts the passed value from `WEI` to token decimals
     * @param _decimals Number of decimals the target token has (Is dynamic)
     * @param _amount Amount that has to be converted from the current token decimals to 18 decimals
     */
    function tokenDecimalsToWei(uint256 _decimals, uint256 _amount) public pure returns (uint256) {
        return (_amount * Constants.WAD) / 10 ** _decimals;
    }
}
