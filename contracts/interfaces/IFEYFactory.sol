// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";

/**
 * @title IFEYFactory
 * @notice The interface for the Product factory contract
 * @author Struct Finance
 *
 */

interface IFEYFactory {
    /// @dev Emitted when the product is deployed
    event ProductCreated(
        address indexed productAddress,
        uint256 fixedRate,
        uint256 startTimeDeposit,
        uint256 startTimeTranche,
        uint256 endTimeTranche
    );

    /// @dev Emitted when the tranche is created
    event TrancheCreated(
        address indexed productAddress, DataTypes.Tranche trancheType, address indexed tokenAddress, uint256 capacity
    );

    /// @dev Emitted when a token's status gets updated
    event TokenStatusUpdated(address indexed token, uint256 status);

    /// @dev Emitted when a LP is whitelised
    event PoolStatusUpdated(address indexed lpAddress, uint256 status, address indexed tokenA, address indexed tokenB);

    /// @dev Emitted when the FEYProduct implementaion is updated
    event FEYProductImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);

    /// @dev The following events are emitted when respective setter methods are invoked
    event StructPriceOracleUpdated(address indexed structPriceOracle);
    event TrancheDurationMinUpdated(uint256 minTrancheDuration);
    event TrancheDurationMaxUpdated(uint256 maxTrancheDuration);
    event LeverageThresholdMinUpdated(uint256 levThresholdMin);
    event LeverageThresholdMaxUpdated(uint256 levThresholdMax);
    event TrancheCapacityUpdated(uint256 defaultTrancheCapUSD);
    event PerformanceFeeUpdated(uint256 performanceFee);
    event ManagementFeeUpdated(uint256 managementFee);
    event MinimumInitialDepositValueUpdated(uint256 newValue);
    event MaxFixedRateUpdated(uint256 _fixedRateMax);
    event FactoryGACInitialized(address indexed gac);

    /// @dev Emitted when Yieldsource address is added for a LP token
    event YieldSourceAdded(address indexed lpToken, address indexed yieldSource);

    function createProduct(
        DataTypes.TrancheConfig memory _configTrancheSr,
        DataTypes.TrancheConfig memory _configTrancheJr,
        DataTypes.ProductConfigUserInput memory _productConfigUserInput,
        DataTypes.Tranche _tranche,
        uint256 _initialDepositAmount
    ) external payable;

    function isMintActive(uint256 _spTokenId) external view returns (bool);

    function isTransferEnabled(uint256 _spTokenId, address _user) external view returns (bool);
}
