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

    /// @dev Emitted when a LP is whitelised
    event PoolStatusUpdated(address indexed lpAddress, uint256 status, address indexed tokenA, address indexed tokenB);

    event FactoryGACInitialized(address indexed gac);

    /// @dev Emitted when Yieldsource address is added for a LP token
    event YieldSourceAdded(address indexed lpToken, address indexed yieldSource, address tokenA, address tokenB);

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
