// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";

/// @title GMX Yield Source Interface
/// @notice  Defines the functions specific to the GMX yield source contract
interface IGMXYieldSource {
    /// @dev Generic errors

    /// If zero address is passed as an arg
    error ZeroAddress();

    /// Already initialized\
    error Initialized();

    /// No shares for the product yet
    error NoShares(address _product);

    /// _sharesToTokens returns zero during redeem
    error ZeroShares();

    /// Products can supply tokens only once
    error AlreadySupplied();

    /// The expected reward amount is more than the actual rewards added
    error InsufficientRewards(uint256 _actualRewardAmount, uint256 _expectedRewardAmount);

    /// @notice Emitted whenever the tokens are supplied (Buying GLP)
    /// @param amountAIn Amount of tokens A supplied to the LP
    /// @param amountBIn Amount of tokens B supplied to the LP
    /// @param glpReceived GLP Tokens received from the LP in return
    event TokensSupplied(uint256 amountAIn, uint256 amountBIn, uint256 glpReceived);

    /// @notice Emitted whenever the tokens are redeemed from the GLP pool
    /// @param amountARedeemed Amount of tokens A supplied to the LP
    /// @param amountBRedeemed Amount of tokens B supplied to the LP
    event TokensRedeemed(uint256 amountARedeemed, uint256 amountBRedeemed);

    /// @notice Emitted whenever the rewards are harvested and recompounded
    event RewardsRecompounded();

    /// @notice Emitted when additional rewards are added
    /// @param productAddress Address of the product contract
    event RewardsAdded(address indexed productAddress);

    function setFEYGMXProductInfo(address _productAddress, DataTypes.FEYGMXProductInfo memory _productInfo) external;

    /// @notice Supplies liquidity to the GLP index (Buying GLP)
    /// @param amountAIn The amount of token A to be supplied.
    /// @param amountBIn The amount of token B to be supplied.
    /// @return _amountAInWei The amount of token A actually supplied to GLP
    /// @return _amountBInWei The amount of token B actually supplied to GLP
    function supplyTokens(uint256 amountAIn, uint256 amountBIn)
        external
        returns (uint256 _amountAInWei, uint256 _amountBInWei);

    /// @notice Redeems tokens from the GLP index. (Selling GLP)
    /// @dev The redeemed tokens will be directly sent to the product contract triggering the call
    /// @param _expectedTokenAAmount The amount of token A expected to be redeemed
    /// @return The amount of token A received from the GLP
    /// @return The amount of token B received from the GLP

    function redeemTokens(uint256 _expectedTokenAAmount) external returns (uint256, uint256);

    /// @notice Re-compounds rewards
    function recompoundRewards() external;

    function getFEYGMXProductInfo(address _productAddress) external view returns (DataTypes.FEYGMXProductInfo memory);
}
