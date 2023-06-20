// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// Internal Imports
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Helpers} from "../helpers/Helpers.sol";

/**
 * @title Validation library
 * @author Struct Finance
 */
library Validation {
    /**
     * @notice Used to validate the swap paths
     * @param _swapPath The struct of swap paths to validate
     * @param _addresses The address struct
     * @param _isDualReward Specifies if the farm has dual rewards
     * @param _tokenSr The address of the senior tranche token
     * @param _tokenJr  The address of the junior tranche token
     */
    function validatePaths(
        DataTypes.SwapPath memory _swapPath,
        DataTypes.Addresses memory _addresses,
        address _tokenSr,
        address _tokenJr,
        bool _isDualReward
    ) external pure {
        /// @dev `seniorToJunior` and  `juniorToSenior` paths should always be length 2 (pool should always exist)
        require(address(_swapPath.seniorToJunior[0]) == _tokenSr, Errors.PE_SR_TO_JR_1);
        require(address(_swapPath.seniorToJunior[1]) == _tokenJr, Errors.PE_SR_TO_JR_2);
        require(_swapPath.seniorToJunior.length == 2, Errors.VE_INVALID_LENGTH);
        require(address(_swapPath.juniorToSenior[0]) == _tokenJr, Errors.PE_JR_TO_SR_1);
        require(address(_swapPath.juniorToSenior[1]) == _tokenSr, Errors.PE_JR_TO_SR_2);
        require(_swapPath.juniorToSenior.length == 2, Errors.VE_INVALID_LENGTH);

        /// @dev All the other paths can have 1 hop at max
        require(address(_swapPath.nativeToSenior[0]) == address(_addresses.nativeToken), Errors.PE_NATIVE_TO_SR_1);
        require(
            address(_swapPath.nativeToSenior[_swapPath.nativeToSenior.length - 1]) == _tokenSr, Errors.PE_NATIVE_TO_SR_2
        );

        require(_swapPath.nativeToSenior.length < 4, Errors.VE_INVALID_LENGTH);

        require(_swapPath.nativeToJunior[0] == address(_addresses.nativeToken), Errors.PE_NATIVE_TO_JR_1);
        require(_swapPath.nativeToJunior[_swapPath.nativeToJunior.length - 1] == _tokenJr, Errors.PE_NATIVE_TO_JR_2);
        require(_swapPath.nativeToJunior.length < 4, Errors.VE_INVALID_LENGTH);

        require(address(_swapPath.reward1ToNative[0]) == address(_addresses.reward1), Errors.PE_REWARD1_TO_NATIVE_1);

        require(
            address(_swapPath.reward1ToNative[_swapPath.reward1ToNative.length - 1]) == address(_addresses.nativeToken),
            Errors.PE_REWARD1_TO_NATIVE_2
        );
        require(_swapPath.reward1ToNative.length < 4, Errors.VE_INVALID_LENGTH);

        if (_isDualReward) {
            require(address(_swapPath.reward2ToNative[0]) == address(_addresses.reward2), Errors.PE_REWARD2_TO_NATIVE_1);

            require(
                address(_swapPath.reward2ToNative[_swapPath.reward2ToNative.length - 1])
                    == address(_addresses.nativeToken),
                Errors.PE_REWARD2_TO_NATIVE_2
            );
            require(_swapPath.reward2ToNative.length < 4, Errors.VE_INVALID_LENGTH);
        }
    }

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
        IERC1155 _spToken,
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
}
