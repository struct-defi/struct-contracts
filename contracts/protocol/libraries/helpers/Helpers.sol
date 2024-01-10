// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Internal Imports
import {IJoeRouter} from "../../../external/traderjoe/IJoeRouter.sol";
import {ILBQuoter} from "../../../external/traderjoe/ILBQuoter.sol";

import {IWETH9} from "../../../external/IWETH9.sol";

import {IStructPriceOracle} from "../../../interfaces/IStructPriceOracle.sol";
import {ISPToken} from "../../../interfaces/ISPToken.sol";

import {DataTypes} from "../types/DataTypes.sol";
import {Constants} from "./Constants.sol";
import {Errors} from "./Errors.sol";
import {JoeLibrary} from "./JoeLibraryModified.sol";

/**
 * @title Helpers library
 * @notice Collection of helper functions
 * @author Struct Finance
 */
library Helpers {
    using Arrays for uint256[];
    using SafeERC20 for IERC20Metadata;

    /// @dev Emits when the performance fee is sent to the feeReceiver
    event PerformanceFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);

    /// @dev Emits when the management fee is sent to the feeReceiver
    event ManagementFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);

    /// @dev Emits the total fees charged for each tranche
    event FeeCharged(uint256 feeTotalSr, uint256 feeTotalJr);

    /**
     * @dev Given the total amount invested, we want to find
     *   out how many of this investor's deposits were actually
     *   used. Use findUpperBound on the prefixSum to find the point
     *   where total deposits were accepted. For example, if $2000 was
     *   deposited by all investors and $1000 was invested, then some
     *   position in the prefixSum splits the array into deposits that
     *   got in, and deposits that didn't get in. That same position
     *   maps to userSums. This is the user's deposits that got
     *   in. Since we are keeping track of the sums, we know at that
     *   position the total deposits for a user was $15, even if it was
     *   15 $1 deposits. And we know the amount that didn't get in is
     *   the last value in userSum - the amount that got it.
     *
     * @param investor A specific investor
     * @param invested The total amount invested
     */
    function getInvestedAndExcess(DataTypes.Investor storage investor, uint256 invested)
        external
        view
        returns (uint256 userInvested, uint256 excess)
    {
        uint256[] storage prefixSums_ = investor.depositSums;
        uint256 length = prefixSums_.length;
        if (length == 0) {
            // There were no deposits. Return 0, 0.
            return (userInvested, excess);
        }
        uint256 leastUpperBound = prefixSums_.findUpperBound(invested);
        if (length == leastUpperBound) {
            // All deposits got in, no excess. Return total deposits, 0
            userInvested = investor.userSums[length - 1];
            return (userInvested, excess);
        }
        uint256 prefixSum = prefixSums_[leastUpperBound];
        if (prefixSum == invested) {
            // Not all deposits got in, but there are no partial deposits
            userInvested = investor.userSums[leastUpperBound];
        } else {
            // Let's say some of my deposits got in. The last deposit,
            // however, was $100 and only $30 got in. Need to split that
            // deposit so $30 got in, $70 is excess.
            userInvested = leastUpperBound > 0 ? investor.userSums[leastUpperBound - 1] : 0;
            uint256 depositAmount = investor.userSums[leastUpperBound] - userInvested;
            if (prefixSum - depositAmount < invested) {
                userInvested += (depositAmount + invested - prefixSum);
                excess = investor.userSums[length - 1] - userInvested;
            }
        }
        excess = investor.userSums[length - 1] - userInvested;
    }

    /**
     * @notice This methods calculates the relative percentage difference.
     * @param _rate1 Rate from the AMM
     * @param _rate2 Rate from the Chainlink price feed
     * @return A flag that states whether the given rates lies within the `MAX_DEVIATION`
     */
    function _isWithinBound(uint256 _rate1, uint256 _rate2) public pure returns (bool) {
        uint256 _relativeChangePct;
        if (_rate1 > _rate2) {
            _relativeChangePct = ((_rate1 - _rate2) * Constants.DECIMAL_FACTOR * Constants.WAD) / _rate2;
        } else {
            _relativeChangePct = ((_rate2 - _rate1) * Constants.DECIMAL_FACTOR * Constants.WAD) / _rate1;
        }
        return _relativeChangePct <= Constants.MAX_DEVIATION * Constants.WAD ? true : false;
    }

    /**
     * @notice Used to calculate fees to be sent to the receiver once the funds are withdrawn from LP
     * @param _tokensInvestableSr The total amount of Senior tranche tokens that were eligible for investment
     * @param _tokensAtMaturitySr The total amount of Senior tranche tokens withdrawn after maturity
     * @param _tokensInvestableJr The total amount of Junior tranche tokens that were eligible for investment
     * @param _tokensAtMaturityJr The total amount of Junior tranche tokens withdrawn after maturity
     * @param _productConfig The configuration/specs of the product
     * @return _srFeeTotal The total fee charged as senior tranche tokens
     * @return _jrFeeTotal The total fee charged as junior tranche tokens
     */
    function calculateFees(
        uint256 _tokensInvestableSr,
        uint256 _tokensAtMaturitySr,
        uint256 _tokensInvestableJr,
        uint256 _tokensAtMaturityJr,
        DataTypes.ProductConfig storage _productConfig
    ) external returns (uint256, uint256) {
        uint256 feeTotalJr;
        uint256 feeTotalSr;

        /// Performance Fee
        if (_productConfig.performanceFee > 0) {
            if (_tokensAtMaturitySr > _tokensInvestableSr) {
                uint256 _srPerfFee = (_productConfig.performanceFee * (_tokensAtMaturitySr - _tokensInvestableSr))
                    / Constants.DECIMAL_FACTOR;
                feeTotalSr += _srPerfFee;
                emit PerformanceFeeSent(DataTypes.Tranche.Senior, _srPerfFee);
            }

            if (_tokensAtMaturityJr > _tokensInvestableJr) {
                uint256 _jrPerfFee = (_productConfig.performanceFee * (_tokensAtMaturityJr - _tokensInvestableJr))
                    / Constants.DECIMAL_FACTOR;
                feeTotalJr += _jrPerfFee;
                emit PerformanceFeeSent(DataTypes.Tranche.Junior, _jrPerfFee);
            }
        }

        emit FeeCharged(feeTotalSr, feeTotalJr);
        return (feeTotalSr, feeTotalJr);
    }

    /**
     * @dev Sends the specified % of the fee to the recipient
     * @param _joeRouter Interface for the joeRouter contract
     * @param _feeTotalSr Total fees accumulated from the senior tranche
     * @param _feeTotalJr Total fees accumulated from the junior tranche
     * @param _seniorToNative Swap path array for the senior to native token
     * @param _juniorToNative Swap path array for the junior to native token
     * @param _feeReceiver Address of the fee receiver (distribution manager)
     */
    function swapAndSendFeeToReceiver(
        IJoeRouter _joeRouter,
        uint256 _feeTotalSr,
        uint256 _feeTotalJr,
        address[] calldata _seniorToNative,
        address[] calldata _juniorToNative,
        address _feeReceiver
    ) external {
        address _nativeToken = _seniorToNative[_seniorToNative.length - 1];

        if (_feeTotalSr > 0) {
            _sendReceiverFee(_joeRouter, _feeTotalSr, _seniorToNative, _feeReceiver, _nativeToken);
        }

        if (_feeTotalJr > 0) {
            _sendReceiverFee(_joeRouter, _feeTotalJr, _juniorToNative, _feeReceiver, _nativeToken);
        }
    }

    /**
     * @notice Send the receiver fee.
     * @param _joeRouter Interface for the joeRouter contract
     * @param _feeTotal Total fees accumulated by product
     * @param _path Swap path
     * @param _feeReceiver Address of the fee receiver (distribution manager)
     * @param _nativeToken Address of the native token (WAVAX)
     */
    function _sendReceiverFee(
        IJoeRouter _joeRouter,
        uint256 _feeTotal,
        address[] calldata _path,
        address _feeReceiver,
        address _nativeToken
    ) private {
        if (_path[0] == _nativeToken) {
            IERC20Metadata(_nativeToken).safeTransfer(_feeReceiver, _feeTotal);
        } else {
            uint256 _amountIn = weiToTokenDecimals(IERC20Metadata(_path[0]).decimals(), _feeTotal);
            IERC20Metadata(_path[0]).safeIncreaseAllowance(address(_joeRouter), _amountIn);
            _joeRouter.swapExactTokensForTokens(_amountIn, 0, _path, _feeReceiver, block.timestamp);
        }
    }

    /**
     * @notice Converts AVAX to wAVAX for deposit
     * @param _depositAmount The amount the user wishes to deposit in AVAX
     * @param wAVAX The address of the native tokens
     */
    function _wrapAVAXForDeposit(uint256 _depositAmount, address payable wAVAX) external {
        require(_depositAmount == msg.value, Errors.VE_INVALID_INPUT_AMOUNT);
        IWETH9(payable(address(wAVAX))).deposit{value: _depositAmount}();
    }

    /**
     * @notice Returns the price of the given asset
     * @param _structPriceOracle The oracle address of Struct price feed
     * @param _asset The address of the asset
     */
    function getAssetPrice(IStructPriceOracle _structPriceOracle, address _asset) public view returns (uint256) {
        return _structPriceOracle.getAssetPrice(_asset);
    }

    /**
     * @notice Validates and returns the exchange rate for the given assets from the chainlink oracle and AMM.
     * @dev This is required to prevent oracle manipulation attacks.
     * @param _structPriceOracle The oracle address of Struct price feed
     * @param _path The path to get the exchange rate from the AMM (LP)
     * @param _lbQuoter The address of the TJ LB Quoter contract
     * @param _amountOut The amount of tokens to be swapped out
     */
    function getTrancheTokenRateV2(
        IStructPriceOracle _structPriceOracle,
        address[] storage _path,
        ILBQuoter _lbQuoter,
        uint256 _amountOut
    ) external view returns (bool, uint256, uint256, uint256) {
        uint256 _toTokenIndex = _path.length - 1;
        uint256 _priceAsset1 = _structPriceOracle.getAssetPrice(_path[0]);
        uint256 _priceAsset2 = _structPriceOracle.getAssetPrice(_path[_toTokenIndex]);
        /// Calculate the exchange rate using the prices from StructPriceOracle (Chainlink price feed)
        uint256 _chainlinkRate = (_priceAsset1 * Constants.WAD) / _priceAsset2;

        ILBQuoter.Quote memory quote;
        uint256 _ammRate;
        /// Calculate the exchange rate using the Router
        if (_amountOut == 0) {
            quote = _lbQuoter.findBestPathFromAmountIn(_path, uint128(10 ** IERC20Metadata(_path[0]).decimals()));
            // no need to divide by the amountIn because it is equivalent to WAD
            _ammRate = tokenDecimalsToWei(IERC20Metadata(_path[_toTokenIndex]).decimals(), quote.amounts[_toTokenIndex]);
        } else {
            /// if amountOut < 1 token, set it to 10 ** decimals to avoid incorrect rate
            if (_amountOut < 10 ** IERC20Metadata(_path[_toTokenIndex]).decimals()) {
                _amountOut = 10 ** IERC20Metadata(_path[_toTokenIndex]).decimals();
            }
            _amountOut = weiToTokenDecimals(IERC20Metadata(_path[_toTokenIndex]).decimals(), _amountOut);
            quote = _lbQuoter.findBestPathFromAmountOut(_path, uint128(_amountOut));
            _ammRate = tokenDecimalsToWei(IERC20Metadata(_path[_toTokenIndex]).decimals(), quote.amounts[_toTokenIndex])
                * Constants.WAD / tokenDecimalsToWei(IERC20Metadata(_path[0]).decimals(), quote.amounts[0]);
        }

        /// Check if the relative price diff % is within the MAX_DEVIATION
        /// if yes, return the exchange rate and chainlink price along with a flag
        /// if not, return the price and rate as 0 along with false flag
        return _isWithinBound(_chainlinkRate, _ammRate)
            ? (true, _ammRate, _priceAsset1, _priceAsset2)
            : (false, 0, _priceAsset1, _priceAsset2);
    }

    /**
     * @notice Converts the passed value from `WEI` to token decimals
     * @param _decimals Number of decimals the target token has (Is dynamic)
     * @param _amount Amount that has to be converted from the current token decimals to 18 decimals
     */
    function tokenDecimalsToWei(uint256 _decimals, uint256 _amount) public pure returns (uint256) {
        return (_amount * Constants.WAD) / 10 ** _decimals;
    }

    /**
     * @notice Converts the passed value from token decimals to `WEI`
     * @param _decimals Number of decimals the target token has (Is dynamic)
     * @param _amount Amount that has to be converted from 18 decimals to the current token decimals
     */
    function weiToTokenDecimals(uint256 _decimals, uint256 _amount) public pure returns (uint256) {
        return (_amount * 10 ** _decimals) / Constants.WAD;
    }

    function _getTokenBalance(IERC20Metadata _token, address _account) internal view returns (uint256 _balance) {
        _balance = _token.balanceOf(_account);
    }
}
