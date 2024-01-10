// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// Internal Imports
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Helpers} from "../helpers/Helpers.sol";
import {Constants} from "../helpers/Constants.sol";
import {IFEYProduct} from "../../../interfaces/IFEYProduct.sol";
import {ISPToken} from "../../../interfaces/ISPToken.sol";

/**
 * @title Validation library
 * @author Struct Finance
 */
library Validation {
    /**
     * @notice Used to validate the deposits
     * @param _trancheStartTime The start time of the tranche
     * @param _trancheCapacity The max capacity of the tranche
     * @param _depositStartTime The start time of the deposits
     * @param _depositsTotal Total deposits so far into the pool
     * @param _amount  The amount of tokens to be deposited
     * @param _decimals The decimal of the token to be deposited
     */
    function validateDeposit(
        uint256 _trancheStartTime,
        uint256 _trancheCapacity,
        uint256 _depositStartTime,
        uint256 _depositsTotal,
        uint256 _amount,
        uint256 _decimals
    ) external view {
        require(_amount > 0, Errors.VE_INVALID_DEPOSIT_AMOUNT);
        require(block.timestamp >= _depositStartTime, Errors.VE_DEPOSITS_NOT_STARTED);

        require(block.timestamp < _trancheStartTime, Errors.VE_DEPOSITS_CLOSED);

        require(
            Helpers.tokenDecimalsToWei(_decimals, _amount) + _depositsTotal <= _trancheCapacity,
            Errors.VE_AMOUNT_EXCEEDS_CAP
        );
    }

    /**
     * @notice Used to validate the invest method
     * @param _trancheStartTime The start time of the tranche
     * @param _currentState The current state of the contract
     * @param _trancheCapSr The capacity of the senior tranche
     * @param _trancheCapJr The capacity of the junior tranche
     * @param _tokensDepositedSr The tokens deposited so far to the senior tranche
     * @param _tokensDepositedJr The tokens deposited so far to the junior tranche
     */
    function validateInvest(
        uint256 _trancheStartTime,
        DataTypes.State _currentState,
        uint256 _trancheCapSr,
        uint256 _trancheCapJr,
        uint256 _tokensDepositedSr,
        uint256 _tokensDepositedJr
    ) external view {
        /// Tokens can be invested to the LP before `trancheStartTime`  if the tranches are full
        require(
            (_trancheCapSr == _tokensDepositedSr && _trancheCapJr == _tokensDepositedJr)
                || block.timestamp >= _trancheStartTime,
            Errors.VE_TRANCHE_NOT_STARTED
        );
        require(_currentState == DataTypes.State.OPEN, Errors.VE_INVALID_STATE);
    }

    /**
     * @notice Used to validate the `removeFunds()` method
     *
     * @param _trancheEndTime The end time of the tranche
     * @param _currentState The current state of the contract
     */
    function validateRemoveFunds(uint256 _trancheEndTime, DataTypes.State _currentState) external view {
        require(_currentState == DataTypes.State.INVESTED, Errors.VE_INVALID_STATE);
        require(block.timestamp >= _trancheEndTime, Errors.VE_NOT_MATURED);
    }

    /**
     * @notice Used to validate the `claimExcess()` method
     * @param _investor The address of the investor who calls the method
     * @param _trancheInfo The info of the tranche
     * @param _currentState The current state of the product contract
     */
    function validateClaimExcess(
        DataTypes.State _currentState,
        DataTypes.Investor storage _investor,
        DataTypes.TrancheInfo memory _trancheInfo
    ) external view returns (uint256 _userInvested, uint256 _excess) {
        require(_currentState != DataTypes.State.OPEN, Errors.VE_INVALID_STATE);
        require(!_investor.claimed, Errors.VE_ALREADY_CLAIMED);

        (_userInvested, _excess) = Helpers.getInvestedAndExcess(_investor, _trancheInfo.tokensInvestable);
        require(_excess > 0, Errors.VE_NO_EXCESS);
    }

    /**
     * @notice Used to validate the `withdraw()` method
     * @param _currentState The current state of the product
     * @param _spToken The StructSPToken
     * @param _spTokenId The StructSPTokenId for the tranche
     * @param _investor The investor struct to calculate tokens excess
     * @param _tokensInvestable The total tokens that were eligible for investment from the tranche
     */
    function validateWithdrawal(
        DataTypes.State _currentState,
        ISPToken _spToken,
        uint256 _spTokenId,
        DataTypes.Investor storage _investor,
        uint256 _tokensInvestable
    ) external view {
        require(_currentState == DataTypes.State.WITHDRAWN, Errors.VE_INVALID_STATE);
        require(_spToken.balanceOf(msg.sender, _spTokenId) > 0, Errors.VE_INSUFFICIENT_BAL);
        (, uint256 _excess) = Helpers.getInvestedAndExcess(_investor, _tokensInvestable);

        /// The user should claim the excess before withdrawing from the tranche
        require(_excess == 0 || _investor.claimed, Errors.VE_NOT_CLAIMED_YET);
    }

    /**
     * @notice Checks the total SP token balance == tranche tokens owned by the product contract.
     * @param _tranche The tranche for which the balances need to be computed.
     */
    function checkSpAndTrancheTokenBalances(address _productAddress, DataTypes.Tranche _tranche, ISPToken _spToken)
        external
        view
    {
        IFEYProduct _product = IFEYProduct(_productAddress);
        DataTypes.TrancheConfig memory _trancheConfig = _product.getTrancheConfig(_tranche);
        uint256 _spTokenSupply = _spToken.totalSupply(_trancheConfig.spTokenId);
        uint256 _tokenBalance = _trancheConfig.tokenAddress.balanceOf(_productAddress);

        DataTypes.Tranche _oppositeTranche =
            _tranche == DataTypes.Tranche.Senior ? DataTypes.Tranche.Junior : DataTypes.Tranche.Senior;
        DataTypes.TrancheConfig memory _oppositeTrancheConfig = _product.getTrancheConfig(_oppositeTranche);

        /// if the senior and junior tranche tokens are the same
        /// then we need to add the opposite tranche's spToken supply
        if (address(_trancheConfig.tokenAddress) == address(_oppositeTrancheConfig.tokenAddress)) {
            _spTokenSupply += _spToken.totalSupply(_oppositeTrancheConfig.spTokenId);
        }
        _spTokenSupply = weiToTokenDecimals(_trancheConfig.decimals, _spTokenSupply);
        require(_tokenBalance >= _spTokenSupply, Errors.VE_DEPOSIT_INVARIANT_CHECK);
    }

    /**
     * @notice Converts the passed value from token decimals to `WEI`
     * @param _decimals Number of decimals the target token has (Is dynamic)
     * @param _amount Amount that has to be converted from 18 decimals to the current token decimals
     */
    function weiToTokenDecimals(uint256 _decimals, uint256 _amount) public pure returns (uint256) {
        return (_amount * 10 ** _decimals) / Constants.WAD;
    }
}
