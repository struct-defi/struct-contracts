// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/// External Imports
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library DataTypes {
    /// @notice It contains the details of the tranche
    struct TrancheInfo {
        /// Actual deposits of the users (aggregate) that are being queued
        uint256 tokensDeposited;
        /// Number of tokens that are eligible for investment into a pool per tranche
        uint256 tokensInvestable;
        /// Tokens that cannot be tokensInvested
        uint256 tokensExcess;
        /// Tokens invested into AMM
        uint256 tokensInvested;
        /// Tracks the tokens available on maturity
        uint256 tokensAtMaturity;
        /// Tracks the tokens received from the AMM's liquidity pool
        uint256 tokensReceivedFromLP;
    }

    /// @notice It contains the configuration of the tranche
    /// @dev It is populated during product creation
    struct TrancheConfig {
        /// Contract address of the tranche token
        IERC20Metadata tokenAddress;
        /// Tranche Token decimals
        uint256 decimals;
        /// Token ID of StructSP tokens for the tranche
        uint256 spTokenId;
        /// Maximum tokens that can be deposited
        uint256 capacity;
    }

    /// @notice It contains the general configuration of the product
    /// @dev It is populated during product creation
    struct ProductConfig {
        /// ID of the pool (for recompunding)
        uint256 poolId;
        /// Interest rate
        uint256 fixedRate;
        /// The timestamp after which users can deposit tokens into the tranches.
        uint256 startTimeDeposit;
        /// The start timestamp of the tranche.
        uint256 startTimeTranche;
        /// The end timestamp of the tranche (Maturity).
        uint256 endTimeTranche;
        ///  The minimum ratio required for deposit to be tokensInvested
        uint256 leverageThresholdMin;
        ///  The maximum ratio required for deposit to be tokensInvested
        uint256 leverageThresholdMax;
        /// The management fee %
        uint256 managementFee;
        /// The performance fee %
        uint256 performanceFee;
    }

    /// @notice It contains the properties of the product configuration set by the user
    /// @dev The properties are reassigned to ProductConfig during product creation
    struct ProductConfigUserInput {
        /// Interest rate
        uint256 fixedRate;
        /// The start timestamp of the tranche.
        uint256 startTimeTranche;
        /// The end timestamp of the tranche (Maturity).
        uint256 endTimeTranche;
        ///  The minimum ratio required for deposit to be tokensInvested
        uint256 leverageThresholdMin;
        ///  The maximum ratio required for deposit to be tokensInvested
        uint256 leverageThresholdMax;
    }

    /**
     * @notice
     *  OPEN - Product contract has been created, and still open for deposits
     *  INVESTED - Funds has been deposited into LP
     *  WITHDRAWN -  Funds have been withdrawn from LP
     */
    enum State {
        OPEN,
        INVESTED,
        WITHDRAWN
    }

    enum Tranche {
        Senior,
        Junior
    }

    /// @dev Swap path types for setter function
    enum SwapPathType {
        SeniorToNative,
        JuniorToNative,
        NativeToSenior,
        NativeToJunior,
        Reward2ToNative,
        NativeToTokenA,
        NativeToTokenB,
        TokenAToTokenB,
        TokenBToTokenA
    }

    /// @notice Struct used to store the details of the investor
    /// @dev Inspired by Ondo Finance
    struct Investor {
        uint256[] userSums;
        uint256[] depositSums;
        uint256 spTokensStaked;
        bool claimed;
        bool depositedNative;
    }

    /// @notice Struct of arrays containing all the routes for swap
    struct SwapPath {
        address[] seniorToJunior;
        address[] juniorToSenior;
        address[] nativeToSenior;
        address[] nativeToJunior;
        address[] seniorToNative;
        address[] juniorToNative;
        address[] reward1ToNative;
        address[] reward2ToNative;
    }

    // Contains tranche config to prevent stack too deep
    struct InitConfigParam {
        DataTypes.TrancheConfig configTrancheSr;
        DataTypes.TrancheConfig configTrancheJr;
        DataTypes.ProductConfig productConfig;
    }

    /// @notice The struct contains the product info for the FEYGMXProducts
    /// @custom: tokenA Address of the tokenA
    /// @custom: tokenB Address of tokenB
    /// @custom: tokenADecimals Decimals of tokenA
    /// @custom: tokenBDecimals Decimals of tokenB
    /// @custom: fsGLPReceived The amount of fsGLPReceived
    /// @custom: shares The shares of the product
    /// @custom: sameToken Whether the tokens are the same
    struct FEYGMXProductInfo {
        address tokenA;
        uint8 tokenADecimals;
        address tokenB;
        uint8 tokenBDecimals;
        uint256 fsGLPReceived;
        uint256 shares;
        bool sameToken;
    }

    /// @notice The struct contains the product and share details for the given AutoPool redemption round.
    /// @custom: totalShares Total product shares to be queued for withdrawal.
    /// @custom: totalAutoPoolTokens Total amount of AutoPool share tokens queued for withdrawal.
    /// @custom: redeemed  Flag to mark if the current round redeemed or not.
    /// @custom: products Address of product contracts queued for withdrawal for the specific round.
    /// @custom: shares Shares of product at the time when queued for withdrawal.
    struct Round {
        uint256 totalShares;
        uint256 totalAutoPoolTokens;
        bool redeemed;
        address[] products;
        uint256[] shares;
    }
}
