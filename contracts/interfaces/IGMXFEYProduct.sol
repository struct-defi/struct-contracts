// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/// Internal Imports
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import "./ISPToken.sol";
import "./IDistributionManager.sol";
import "./IGAC.sol";

import "./IStructPriceOracle.sol";

/**
 * @title The GMX FEYProduct Interface
 * @author Struct Finance
 *
 */
interface IGMXFEYProduct {
    /// @dev Emitted the total amount deposited and the user address whenever deposited to a tranche
    event Deposited(
        DataTypes.Tranche _tranche,
        uint256 _trancheDepositedAmount,
        address indexed _user,
        uint256 _trancheDepositedTotal
    );

    /// @dev Emitted the total amount of senior and junior tokens at maturity along with the fee
    event RemovedFundsFromLP(uint256 _srTokensReceived, uint256 _jrTokensReceived, address indexed _user);

    /// @dev Emitted when the product invests the funds to the liquidity pool
    event Invested(
        uint256 _trancheTokensInvestedSenior,
        uint256 _trancheTokensInvestedJunior,
        uint256 _trancheTokensInvestableSenior,
        uint256 _trancheTokensInvestableJunior
    );

    /// @dev Emitted when the performance fee is sent to the feeReceiver
    event PerformanceFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);

    /// @dev Emitted when the management fee is sent to the feeReceiver
    event ManagementFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);

    /// @dev Emitted when there is a status update
    event StatusUpdated(DataTypes.State status);

    /// @dev Emitted when the tranche is created
    event TrancheCreated(DataTypes.Tranche trancheType, address indexed tokenAddress, uint256 trancheCapacityMax);

    /// @dev Emitted when the user claims the excess tokens
    event ExcessClaimed(
        DataTypes.Tranche _tranche,
        uint256 _spTokenId,
        uint256 _userInvested,
        uint256 _excessAmount,
        address indexed _user
    );

    /// @dev Emitted when the user withdraws from the pool
    event Withdrawn(DataTypes.Tranche _tranche, uint256 _amount, address indexed _user);

    function initialize(
        DataTypes.InitConfigParam memory _initConfig,
        IStructPriceOracle _structPriceOracle,
        ISPToken _spToken,
        IGAC _globalAccessControl,
        IDistributionManager _distributionManager,
        address _yieldSource,
        address payable _nativeToken
    ) external;

    function deposit(DataTypes.Tranche _tranche, uint256 _amount) external payable;

    function depositFor(DataTypes.Tranche _tranche, uint256 _amount, address _onBehalfOf) external payable;

    function invest() external;

    function removeFundsFromLP() external;

    function claimExcessAndWithdraw(DataTypes.Tranche _tranche) external;

    function claimExcess(DataTypes.Tranche _tranche) external;

    function withdraw(DataTypes.Tranche _tranche) external;

    function getProductConfig() external view returns (DataTypes.ProductConfig memory);

    function getTrancheConfig(DataTypes.Tranche _tranche) external view returns (DataTypes.TrancheConfig memory);

    function getTrancheInfo(DataTypes.Tranche _tranche) external view returns (DataTypes.TrancheInfo memory);

    function getUserInvestmentAndExcess(DataTypes.Tranche _tranche, address _invested)
        external
        view
        returns (uint256, uint256);

    function getUserTotalDeposited(DataTypes.Tranche _tranche, address _investor) external view returns (uint256);

    function getCurrentState() external view returns (DataTypes.State);

    function getInvestorDetails(DataTypes.Tranche _tranche, address _user)
        external
        view
        returns (DataTypes.Investor memory);
}
