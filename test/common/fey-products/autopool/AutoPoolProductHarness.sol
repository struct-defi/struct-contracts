// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@core/products/autopool/FEYAutoPoolProduct.sol";

import "@core/libraries/helpers/Helpers.sol";

import "../../../../contracts/utils/WadMath.sol";

contract AutoPoolProductHarness is FEYAutoPoolProduct {
    using WadMath for uint256;
    using SafeERC20 for IERC20Metadata;

    mapping(address => uint256) public trancheTokenBalanceBefore;
    mapping(address => uint256) public trancheTokenBalanceAfter;

    function recordTrancheTokenBalance(IERC20Metadata _token, bool _isBefore) public {
        if (_isBefore) {
            trancheTokenBalanceBefore[address(_token)] = _token.balanceOf(address(this));
        } else {
            trancheTokenBalanceAfter[address(_token)] = _token.balanceOf(address(this));
        }
    }

    function setTokensAtMaturity(DataTypes.Tranche _tranche, uint256 _amount) external {
        trancheInfo[_tranche].tokensAtMaturity = _amount;
    }

    function setTokensInvestable(DataTypes.Tranche _tranche, uint256 _amount) external {
        trancheInfo[_tranche].tokensInvestable = _amount;
    }

    function setExcessClaimed(DataTypes.Tranche _tranche, address _user, bool _status) external {
        investors[_tranche][_user].claimed = _status;
    }

    function setCurrentState(DataTypes.State _state) external {
        currentState = _state;
    }

    function srFrFactor_exposed(uint256 _durationInSeconds) public view returns (uint256 srFrFactor) {
        srFrFactor = (
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable * Constants.YEAR_IN_SECONDS
                + trancheInfo[DataTypes.Tranche.Senior].tokensInvestable * productConfig.fixedRate * _durationInSeconds
                    / Constants.DECIMAL_FACTOR
        ) / Constants.YEAR_IN_SECONDS;
    }

    function allocateToTranches_exposed(uint256 _receivedSr, uint256 _receivedJr, uint256 _srFrFactor)
        external
        returns (uint256 _amountSwapped, DataTypes.Tranche _trancheSwappedFrom)
    {
        uint256 _amountToSwap;
        /// If the senior tranche tokens received from the liquidity pool is larger than the expected amount
        /// Swap the excess to junior tranche tokens
        if (_receivedSr > _srFrFactor) {
            _amountToSwap = _receivedSr - _srFrFactor;
            (bool _isPriceValidSr, uint256 _jrToSrRate,,) = getTokenRate(DataTypes.Tranche.Senior, 0);
            require(_isPriceValidSr, Errors.PFE_INVALID_SR_PRICE);
            uint256 _expectedJrTokens = _jrToSrRate.wadMul(_amountToSwap);
            _swapExact(
                _amountToSwap,
                _expectedJrTokens - ((_expectedJrTokens * slippage) / Constants.DECIMAL_FACTOR),
                seniorTokenToJuniorTokenSwapPath,
                address(this)
            );
            _trancheSwappedFrom = DataTypes.Tranche.Senior;
            /// If the senior tranche tokens received from the liquidity pool is smaller than the expected amount
        } else if (_receivedSr < _srFrFactor) {
            uint256 _seniorDelta = _srFrFactor - _receivedSr;
            uint256 _amountOut = Helpers.weiToTokenDecimals(
                IERC20Metadata(juniorTokenToSeniorTokenSwapPath[juniorTokenToSeniorTokenSwapPath.length - 1]).decimals(),
                _seniorDelta
            );

            ILBQuoter.Quote memory _quote =
                lbQuoter.findBestPathFromAmountOut(juniorTokenToSeniorTokenSwapPath, uint128(_amountOut));
            uint256 _amountInMax = _quote.amounts[0];
            _amountInMax += _amountInMax.mulDiv(slippage, Constants.DECIMAL_FACTOR);
            uint256 _amountInMaxWei = Helpers.tokenDecimalsToWei(trancheTokenJr.decimals(), _amountInMax);

            (bool _isPriceValidJr, uint256 _srToJrRate,,) = getTokenRate(DataTypes.Tranche.Junior, _seniorDelta);
            require(_isPriceValidJr, Errors.PFE_INVALID_JR_PRICE);
            uint256 _jrToSwap = (_seniorDelta).wadDiv(_srToJrRate);
            /// And if it is bigger than both junior and senior tranche tokens received from the liquidity pool
            if (_jrToSwap >= _receivedJr || _amountInMaxWei >= _receivedJr) {
                _amountToSwap = _receivedJr; // swap all the received jr tokens to sr
                uint256 _expectedSrTokens = _srToJrRate.wadMul(_amountToSwap);
                _swapExact(
                    _amountToSwap,
                    _expectedSrTokens - ((_expectedSrTokens * slippage) / Constants.DECIMAL_FACTOR),
                    juniorTokenToSeniorTokenSwapPath,
                    address(this)
                );
                /// Swap the necessary amount to fill the expected to senior tranche tokens
            } else {
                _amountToSwap = _jrToSwap;
                _swapToExact(_quote, _amountInMax, _amountOut, address(this));
            }
            _trancheSwappedFrom = DataTypes.Tranche.Junior;
        }

        _amountSwapped = _amountToSwap;

        if (_amountSwapped == 0) {
            /// they are equal and no swaps required
            _trancheSwappedFrom = DataTypes.Tranche.Senior;
        }
    }

    /// identical implementation to `deposit`/`depositFor`/`_deposit`, except the `_amount` variable is not overwritten with
    /// the delta of the product's token balance before and after transfer
    /// this is necessary to test the `validateBalances` modifier, because in order to break the invariant we need to
    /// mock the amount of tokens received to be different than the `tokensDeposited` variable, but we can't do that if
    /// we use `token.balanceOf` to calculate the `_amount`, since foundry does not support mocking two
    ///  different return values from the same function within the same transaction
    function depositHarness(DataTypes.Tranche _tranche, uint256 _amount) external payable nonReentrant gacPausable {
        _depositHarness(_tranche, _amount, msg.sender);
    }

    function depositForHarness(DataTypes.Tranche _tranche, uint256 _amount, address _onBehalfOf)
        external
        payable
        nonReentrant
        gacPausable
        onlyRole(FACTORY)
    {
        _depositHarness(_tranche, _amount, _onBehalfOf);
    }

    function _depositHarness(DataTypes.Tranche _tranche, uint256 _amount, address _investor) internal {
        DataTypes.TrancheConfig memory _trancheConfig = trancheConfig[_tranche];
        DataTypes.TrancheInfo storage _trancheInfo = trancheInfo[_tranche];

        Validation.validateDeposit(
            productConfig.startTimeTranche,
            _trancheConfig.capacity,
            productConfig.startTimeDeposit,
            _trancheInfo.tokensDeposited,
            _amount,
            _trancheConfig.decimals
        );

        DataTypes.Investor storage investor = investors[_tranche][_investor];
        if (msg.value != 0) {
            require(address(_trancheConfig.tokenAddress) == nativeToken, Errors.VE_INVALID_NATIVE_TOKEN_DEPOSIT);
            Helpers._wrapAVAXForDeposit(_amount, nativeToken);
            investor.depositedNative = true;
        } else {
            /// these lines are commented out so that we can test the `validateBalances` modifier
            // uint256 tokenBalanceBefore = _trancheConfig.tokenAddress.balanceOf(address(this));
            _trancheConfig.tokenAddress.safeTransferFrom(msg.sender, address(this), _amount);
            // _amount = _trancheConfig.tokenAddress.balanceOf(address(this)) - tokenBalanceBefore;
        }

        _amount = Helpers.tokenDecimalsToWei(_trancheConfig.decimals, _amount);

        uint256 _totalDeposited = _trancheInfo.tokensDeposited + _amount;
        _trancheInfo.tokensDeposited = _totalDeposited;
        if (investor.userSums.length == 0) {
            investor.userSums.push(_amount);
        } else {
            investor.userSums.push(_amount + investor.userSums[investor.userSums.length - 1]);
        }

        investor.depositSums.push(_totalDeposited);

        spToken.mint(_investor, _trancheConfig.spTokenId, _amount, "0x0");
        Validation.checkSpAndTrancheTokenBalances(address(this), _tranche, spToken);
        emit Deposited(_tranche, _amount, _investor, _totalDeposited);
    }
}
