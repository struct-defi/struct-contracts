// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@core/products/gmx/FEYGMXProduct.sol";
import "@core/libraries/helpers/Helpers.sol";
import "../../../contracts/utils/WadMath.sol";

contract FEYProductHarness is FEYGMXProduct {
    using WadMath for uint256;

    function tokenDecimals() external view returns (uint256 srDecimals, uint256 jrDecimals) {
        srDecimals = _srDecimals;
        jrDecimals = _jrDecimals;
        return (srDecimals, jrDecimals);
    }

    function srFrFactor_exposed(uint256 _fixedRate, uint256 _durationInSeconds, uint256 _tokensInvestable)
        public
        pure
        returns (uint256 srFrFactor)
    {
        srFrFactor = (
            _tokensInvestable * Constants.YEAR_IN_SECONDS
                + _tokensInvestable * _fixedRate * _durationInSeconds / Constants.DECIMAL_FACTOR
        ) / Constants.YEAR_IN_SECONDS;
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
}
