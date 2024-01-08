// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAutoPoolVault} from "../external/traderjoe/IAutoPoolVault.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";

/// @title TraderJoe Autopool yield source interface
/// @notice  Defines the functions specific to the TraderJoe Autopool yield source
interface IAutoPoolYieldSource {
    /// If zero address is passed as an arg
    error ZeroAddress();
    /// Already intialized
    error Initialized();
    /// Product cannot have zero shares (during supply)
    error ZeroShares();
    /// Products can supply tokens only once
    error AlreadySupplied();
    /// No shares for the product yet (during redemption)
    error NoShares();
    /// Cannot transfer native tokens to the receiver
    error NativeTransferFailed();
    /// RoundId passed is greater or equal to the current round in AutoPool for redemption
    /// @param currentRoundId Current round id from the AutoPool
    /// @param inputRoundId RoundId that has been passed as input
    error InvalidRoundId(uint256 currentRoundId, uint256 inputRoundId);
    /// Round is already full
    error RoundOccupied();
    /// Invalid Swap Path Type
    error InvalidSwapPathType();

    /// @notice Emitted whenever the tokens are supplied to a LP
    /// @param amountAIn Tokens A supplied to the LP
    /// @param amountBIn Tokens B supplied to the LP
    /// @param lpReceived LP Tokens received from the LP in  return
    event TokensSupplied(uint256 amountAIn, uint256 amountBIn, uint256 lpReceived);

    /// @notice Emitted whenever the product is queued for redemption
    /// @param productAddress Address of the product contract
    /// @param roundId Redemption roundId
    event RedemptionQueued(address indexed productAddress, uint256 roundId);

    /// @notice Emitted when the redemption has been executed by Autopool
    /// @param productAddress Address of the product contract
    /// @param amountARedeemed Redemption amount for TokenA
    /// @param amountBRedeemed Redemption amount for TokenB
    event TokensRedeemed(address indexed productAddress, uint256 amountARedeemed, uint256 amountBRedeemed);

    /// @notice Emitted when the maxIterations is updated
    /// @param _maxIterations New maxIterations value
    event MaxIterationsUpdated(uint256 _maxIterations);

    /// @notice Emitted when tokens are farmed
    /// @param _aptFarmed Amount of AutoPool Tokens deposited to the APTFarm
    event TokensFarmed(uint256 _aptFarmed);

    /// @notice Emitted when the rewards are recompounded
    /// @param _reward1 Amount of reward1 tokens received on `harvestRewards()` call
    /// @param _reward2 Amount of reward1 tokens received on `harvestRewards()` call
    /// @param _harvestedTokenA Amount of tokenA received by swapping the reward tokens
    /// @param _harvestedTokenB Amount of tokenB received by swapping the reward tokens
    event RewardsRecompounded(uint256 _reward1, uint256 _reward2, uint256 _harvestedTokenA, uint256 _harvestedTokenB);

    /// @notice Emitted when the swap path is updated
    /// @param _swapPath Swap path to be updated
    /// @param _path Updated swap path
    event SwapPathUpdated(DataTypes.SwapPathType _swapPath, address[] _path);

    /// @notice Emitted when the slippage tolerance is updated
    /// @param _newSlippage New slippage tolerance
    event SlippageUpdated(uint256 _newSlippage);

    /// @notice Supplies liquidity to the LP.
    /// @param amountAIn The amount of tokenA to be supplied (in token decimals)
    /// @param amountBIn The amount of tokenB to be supplied (in token decimals)
    /// @return The amount of tokenA actually supplied to LP (in WAD)
    /// @return The amount of tokenB actually supplied to LP (in WAD)
    function supplyTokens(uint256 amountAIn, uint256 amountBIn) external payable returns (uint256, uint256);

    /// @notice Recompounds rewards
    function recompoundRewards() external;

    /// @notice Queue for redemption in the AutoPool.
    function queueForRedemption() external;

    /// @notice Queue for redemption in the AutoPool without recompounding rewards
    /// @notice To call if there is an issue with recompounding
    function queueForRedemptionSansRecompound() external;

    /// @notice Used to execute queued withdrawals for the latest round from AutoPool
    function redeemTokens() external;

    /// @notice Sets the slippage tolerance for swaps
    function setSlippage(uint256 _newSlippage) external;

    /// @notice Returns the token0 address of the pool
    function tokenA() external view returns (IERC20Metadata);

    /// @notice Returns the token1 address of the pool
    function tokenB() external view returns (IERC20Metadata);

    /// @notice Returns the `autoPoolTokenShares` for the given product
    function productAPTShare(address) external view returns (uint256);

    /// @notice Returns the address of the underlying `autoPoolVault`
    function autoPoolVault() external view returns (IAutoPoolVault);

    /// @notice Returns the total shares value
    function totalShares() external view returns (uint256);

    /// @notice Returns the `totalAutoPoolShareTokens` in the YieldSource contract
    function totalAutoPoolShareTokens() external view returns (uint256);

    /// @notice Returns the equivalent `tokenAmount`  for the given amount of `shares`
    /// @dev This function has the `external` modifier as it has to be accessed in the {FEYAutoPoolProductLens} contract
    function sharesToTokens(uint256 _shares, uint256 _currentTotalShares, uint256 _currentTotalExternalShares)
        external
        view
        returns (uint256 tokenAmount);
}
