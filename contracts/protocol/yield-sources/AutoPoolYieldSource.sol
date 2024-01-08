// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

/// External imports
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
/// Internal imports
import {IAutoPoolVault} from "../../external/traderjoe/IAutoPoolVault.sol";
import {IAPTFarm, IRewarder} from "../../external/traderjoe/IAPTFarm.sol";

import {GACManaged} from "../common/GACManaged.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Helpers} from "../libraries/helpers/Helpers.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {Constants} from "../libraries/helpers/Constants.sol";

import {IAutoPoolYieldSource} from "../../interfaces/IAutoPoolYieldSource.sol";
import {IAutoPoolFEYProduct} from "../../interfaces/IAutoPoolFEYProduct.sol";
import {IStructPriceOracle} from "../../interfaces/IStructPriceOracle.sol";

import {IWETH9} from "../../external/IWETH9.sol";
import {YieldSource} from "./YieldSource.sol";
import {WadMath} from "../../utils/WadMath.sol";
import {PercentageMath} from "../../utils/PercentageMath.sol";

import {ILBRouter} from "../../external/traderjoe/ILBRouter.sol";
import {ILBQuoter} from "../../external/traderjoe/ILBQuoter.sol";

/**
 * @title TraderJoe AutoPool Yield Source contract,
 * @dev This contract inherits GACManaged which extends Pausable also uses the GAC for access control
 * @notice Yield source for the FEYTJAutoPoolProduct that generates yield by depositing into TraderJoe AutoPools
 */
contract AutoPoolYieldSource is YieldSource, IAutoPoolYieldSource {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IWETH9;
    using WadMath for uint256;
    using PercentageMath for uint256;

    /*//////////////////////////////////////////////////////////////
                         AUTOPOOL VAULT INFO STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the AutoPoolVault
    IAutoPoolVault public immutable autoPoolVault;

    /// @notice AutoPool Token decimals
    uint256 private immutable autoPoolTokenDecimals;

    /// @notice Address of the AutoPool token farm
    IAPTFarm internal constant APT_FARM = IAPTFarm(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C);

    /// @notice FarmId of the AutoPool vault
    uint256 public aptFarmId;

    /// @notice It will be 1 if there is no rewarder, 2 otherwise
    uint256 public numRewards;

    /// @notice Address of the additional reward token if rewarder exists
    IERC20Metadata public rewardToken2;

    /// @notice Flag that indicates if reward2 is native token
    bool public isReward2Native;

    /// @dev Address of the LiquidityBook router contract
    ILBRouter internal immutable lbRouter = ILBRouter(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);

    /// @dev Address of the LiquidityBook quoter contract
    ILBQuoter internal immutable lbQuoter = ILBQuoter(0x64b57F4249aA99a812212cee7DAEFEDC40B203cD);

    /// @dev Address of the JOE Token contract
    IERC20Metadata internal immutable joeToken = IERC20Metadata(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);

    /*//////////////////////////////////////////////////////////////
                        TOKEN INFO STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the tokenA of the Pool.
    IERC20Metadata public immutable tokenA;

    /// @notice Address of the tokenB of the Pool.
    IERC20Metadata public immutable tokenB;

    /// @notice ERC20 tokenA decimals.
    uint8 private immutable tokenADecimals;

    /// @notice ERC20 tokenB decimals.
    uint8 private immutable tokenBDecimals;

    /*//////////////////////////////////////////////////////////////
                        OTHER INFO STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice the total shares owned by all products that use this contract
    uint256 public totalShares;

    /// @notice the total share tokens owned by all products that use this contract
    uint256 public totalAutoPoolShareTokens;

    /// @notice mapping to track the product shares allocation
    mapping(address => uint256) public productAPTShare;

    /// @notice Index to track the last processed item in the roundIds array for redemption
    uint256 public nextRoundIndexToBeProcessed;

    /// @notice Max no.of iterations during redemption to prevent accidentally exceeding the block gas limit
    uint256 public maxIterations = 5;

    /// @notice Slippage tolerance for `recompoundRewards()`
    uint256 public slippage = Constants.DEFAULT_SLIPPAGE;

    /// @notice Tracks roundIds in which the products are queued for withdrawal
    uint256[] public roundIds;

    /// @notice Redemption Details for each round
    mapping(uint256 => DataTypes.Round) public roundInfo;

    address payable internal constant WAVAX = payable(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IStructPriceOracle public immutable structPriceOracle;

    /*//////////////////////////////////////////////////////////////
                      SWAPPATH STORAGE
    //////////////////////////////////////////////////////////////*/
    address[] public nativeToTokenASwapPath;
    address[] public nativeToTokenBSwapPath;

    address[] public joeToNativeSwapPath;
    address[] public reward2ToNativeSwapPath;

    address[] public tokenAToTokenBSwapPath;
    address[] public tokenBToTokenASwapPath;

    /*//////////////////////////////////////////////////////////////
                      INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the yield source
     * @param _globalAccessControl The GAC contract
     * @param _autoPoolVault The address of the AutoPoolVault
     */
    constructor(IAutoPoolVault _autoPoolVault, IGAC _globalAccessControl, IStructPriceOracle _structPriceOracle) {
        __GACManaged_init(_globalAccessControl);

        tokenA = IERC20Metadata(_autoPoolVault.getTokenX());
        tokenB = IERC20Metadata(_autoPoolVault.getTokenY());

        tokenADecimals = tokenA.decimals();
        tokenBDecimals = tokenB.decimals();

        autoPoolVault = _autoPoolVault;

        structPriceOracle = _structPriceOracle;

        autoPoolTokenDecimals = uint256(_autoPoolVault.decimals());

        _updateFarmInfo(address(_autoPoolVault));

        /// @dev Construct swap path array
        address[] memory _nativeToTokenASwapPath = new address[](2);
        _nativeToTokenASwapPath[0] = address(WAVAX);
        _nativeToTokenASwapPath[1] = address(tokenA);
        nativeToTokenASwapPath = _nativeToTokenASwapPath;

        address[] memory _nativeToTokenBSwapPath = new address[](2);
        _nativeToTokenBSwapPath[0] = address(WAVAX);
        _nativeToTokenBSwapPath[1] = address(tokenB);
        nativeToTokenBSwapPath = _nativeToTokenBSwapPath;

        address[] memory _joeToNativeSwapPath = new address[](2);
        _joeToNativeSwapPath[0] = address(joeToken);
        _joeToNativeSwapPath[1] = address(WAVAX);
        joeToNativeSwapPath = _joeToNativeSwapPath;

        address[] memory _reward2ToNativeSwapPath = new address[](2);
        _reward2ToNativeSwapPath[0] = address(rewardToken2);
        _reward2ToNativeSwapPath[1] = address(WAVAX);
        reward2ToNativeSwapPath = _reward2ToNativeSwapPath;

        address[] memory _tokenAToTokenBSwapPath = new address[](2);
        _tokenAToTokenBSwapPath[0] = address(tokenA);
        _tokenAToTokenBSwapPath[1] = address(tokenB);
        tokenAToTokenBSwapPath = _tokenAToTokenBSwapPath;

        address[] memory _tokenBToTokenASwapPath = new address[](2);
        _tokenBToTokenASwapPath[0] = address(tokenB);
        _tokenBToTokenASwapPath[1] = address(tokenA);
        tokenBToTokenASwapPath = _tokenBToTokenASwapPath;
    }

    /*//////////////////////////////////////////////////////////////
                        YIELDSOURCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IAutoPoolYieldSource
     * @dev Only PRODUCT contracts can call this method
     */
    function supplyTokens(uint256 _amountAIn, uint256 _amountBIn)
        external
        payable
        gacPausable
        nonReentrant
        onlyRole(PRODUCT)
        returns (uint256 _investedTokenA, uint256 _investedTokenB)
    {
        if (productAPTShare[msg.sender] > 0) revert AlreadySupplied();
        _recompoundRewards();

        uint256 _autoPoolShareTokensBefore = autoPoolVault.balanceOf(address(this));

        uint256 _balanceTokenABefore = tokenA.balanceOf(address(this));
        uint256 _balanceTokenBBefore = tokenB.balanceOf(address(this));

        /// Pull tokens from the product contract
        tokenA.safeTransferFrom(msg.sender, address(this), _amountAIn);
        tokenB.safeTransferFrom(msg.sender, address(this), _amountBIn);

        _amountAIn = tokenA.balanceOf(address(this)) - _balanceTokenABefore;
        _amountBIn = tokenB.balanceOf(address(this)) - _balanceTokenBBefore;

        // Inrease token allowance and deposit to AP Vault
        tokenA.safeIncreaseAllowance(address(autoPoolVault), _amountAIn);
        tokenB.safeIncreaseAllowance(address(autoPoolVault), _amountBIn);
        (, _investedTokenA, _investedTokenB) = autoPoolVault.deposit(_amountAIn, _amountBIn);
        uint256 _autoPoolShareTokensReceived = autoPoolVault.balanceOf(address(this)) - _autoPoolShareTokensBefore;

        uint256 _shares = _tokenToShares(_autoPoolShareTokensReceived, totalShares, totalAutoPoolShareTokens);
        if (_shares < 1) revert ZeroShares();

        // Record the product's APT shares
        productAPTShare[_msgSender()] = _shares;

        // Update total shares
        totalShares += _shares;

        /// Update autoPoolShareTokensTotal
        totalAutoPoolShareTokens += _autoPoolShareTokensReceived;

        // Convert invested amount to WEI
        if (tokenADecimals != 18) _investedTokenA = Helpers.tokenDecimalsToWei(tokenADecimals, _investedTokenA);
        if (tokenBDecimals != 18) _investedTokenB = Helpers.tokenDecimalsToWei(tokenBDecimals, _investedTokenB);
        _depositAPTToFarm(_autoPoolShareTokensReceived);

        emit TokensSupplied(_investedTokenA, _investedTokenB, _autoPoolShareTokensReceived);
    }

    /**
     * @notice Used to harvest and reinvest rewards to accure compounded yields
     * @dev Only KEEPER account can call this method
     */
    function recompoundRewards() public gacPausable onlyRole(KEEPER) {
        _recompoundRewards();
    }

    /**
     * @inheritdoc IAutoPoolYieldSource
     * @dev Only PRODUCT contracts can call this method
     */
    function queueForRedemption() external gacPausable nonReentrant onlyRole(PRODUCT) {
        _recompoundRewards();
        _queueForRedemption();
    }

    /**
     * @inheritdoc IAutoPoolYieldSource
     * @dev Only PRODUCT contracts can call this method
     */
    function queueForRedemptionSansRecompound() external gacPausable nonReentrant onlyRole(PRODUCT) {
        _queueForRedemption();
    }

    /**
     * @inheritdoc IAutoPoolYieldSource
     * @dev Only KEEPERS can call this method
     */
    function redeemTokens() external gacPausable nonReentrant onlyRole(KEEPER) {
        /// Fetch the latest round Id
        uint256 _currentRoundId = autoPoolVault.getCurrentRound() - 1;
        uint256[] memory _roundIds = roundIds; //cache
        uint256 _iterations = _roundIds.length;

        // Start processing the arrays from the last processed index
        uint256 _roundIndex = nextRoundIndexToBeProcessed;
        uint256 _numIterations;
        for (; _roundIndex < _iterations;) {
            uint256 _roundId = _roundIds[_roundIndex];
            if (_roundId > _currentRoundId) {
                break;
            }

            /// We only allow 10 processRedemption (maxIteration) to be called for each redeemToken() call.
            /// We will only redeem tokens for a specific round if we can run processRedemption for all products in that round.
            DataTypes.Round storage _roundInfo = roundInfo[_roundId];
            uint256 _productsLength = _roundInfo.products.length;

            if (_productsLength + _numIterations > maxIterations) {
                break;
            }

            uint256 _balanceTokenABefore = tokenA.balanceOf(address(this));
            uint256 _balanceTokenBBefore = tokenB.balanceOf(address(this));

            autoPoolVault.redeemQueuedWithdrawal(_roundId, address(this));

            uint256 tokenAReceived = tokenA.balanceOf(address(this)) - _balanceTokenABefore;
            uint256 tokenBReceived = tokenB.balanceOf(address(this)) - _balanceTokenBBefore;

            for (uint256 _productIndex; _productIndex < _productsLength;) {
                uint256 _tokenARedeemed =
                    _roundInfo.shares[_productIndex].mulDiv(tokenAReceived, _roundInfo.totalShares);
                uint256 _tokenBRedeemed =
                    _roundInfo.shares[_productIndex].mulDiv(tokenBReceived, _roundInfo.totalShares);
                address _productAddress = _roundInfo.products[_productIndex];

                tokenA.safeIncreaseAllowance(_productAddress, _tokenARedeemed);
                tokenB.safeIncreaseAllowance(_productAddress, _tokenBRedeemed);

                IAutoPoolFEYProduct(_productAddress).processRedemption(_tokenARedeemed, _tokenBRedeemed);

                emit TokensRedeemed(_productAddress, _tokenARedeemed, _tokenBRedeemed);

                unchecked {
                    ++_productIndex;
                }
            }

            _roundInfo.redeemed = true;

            unchecked {
                ++_roundIndex;
                _numIterations += _productsLength;
            }
        }
        // Update the index
        nextRoundIndexToBeProcessed = _roundIndex;
    }

    /// @notice See documentation at {YieldSource}
    function sharesToTokens(uint256 _shares, uint256 _currentTotalShares, uint256 _currentTotalExternalShares)
        external
        pure
        returns (uint256)
    {
        return _sharesToTokens(_shares, _currentTotalShares, _currentTotalExternalShares);
    }

    /**
     * @notice Used to updated the `maxIterations` value
     *  @dev Can only be called by accounts with `GOVERNANCE` role
     */
    function setMaxIterations(uint256 _maxIterations) external onlyRole(GOVERNANCE) {
        require(_maxIterations > 0, Errors.VE_INVALID_ZERO_VALUE);
        maxIterations = _maxIterations;
        emit MaxIterationsUpdated(_maxIterations);
    }

    /**
     * @dev Used to update the swap path
     * @param _swapPath The swap path to be updated
     * @param _newPath The new swap path
     */
    function setSwapPath(DataTypes.SwapPathType _swapPath, address[] memory _newPath) external onlyRole(GOVERNANCE) {
        if (_swapPath == DataTypes.SwapPathType.TokenAToTokenB) {
            tokenAToTokenBSwapPath = _newPath;
        } else if (_swapPath == DataTypes.SwapPathType.TokenBToTokenA) {
            tokenBToTokenASwapPath = _newPath;
        } else if (_swapPath == DataTypes.SwapPathType.Reward2ToNative) {
            reward2ToNativeSwapPath = _newPath;
        } else if (_swapPath == DataTypes.SwapPathType.NativeToTokenA) {
            nativeToTokenASwapPath = _newPath;
        } else if (_swapPath == DataTypes.SwapPathType.NativeToTokenB) {
            nativeToTokenBSwapPath = _newPath;
        } else {
            revert InvalidSwapPathType();
        }

        emit SwapPathUpdated(_swapPath, _newPath);
    }

    /**
     * @notice Allows GOVERNANCE to manually harvest rewards from the farm
     */

    function harvestRewards() external onlyRole(GOVERNANCE) {
        _harvestRewards();
    }

    /**
     * @notice Used to rescue tokens that are either stuck or accidentally sent to this contract
     * @param _tokenAddress Address of the ERC20 token
     * @param _amount Amount of the token to be transferred in token decimals
     * @param _recipient The address of the receiver
     * @param _isNative Flag to indicate if the native token should be rescued.
     */

    function rescueTokens(IERC20Metadata _tokenAddress, uint256 _amount, address _recipient, bool _isNative)
        external
        onlyRole(GOVERNANCE)
    {
        if (_recipient == address(0)) revert ZeroAddress();
        _rescueTokens(_tokenAddress, _amount, _recipient, _isNative);
    }

    /**
     * @notice Used to update farm details in case a farm is created for the pool after deployment
     */

    function updateFarmInfo() external onlyRole(GOVERNANCE) {
        _updateFarmInfo(address(autoPoolVault));
        _depositAPTToFarm(autoPoolVault.balanceOf(address(this)));
    }

    /**
     * @notice Used to update slippage
     */

    function setSlippage(uint256 _newSlippage) external onlyRole(GOVERNANCE) {
        slippage = _newSlippage;
        emit SlippageUpdated(_newSlippage);
    }

    /**
     * @notice Used to emergency withdraw AP tokens from the AP farm
     */
    function emergencyWithdrawFromFarm() public onlyRole(GOVERNANCE) {
        if (numRewards > 0) {
            APT_FARM.emergencyWithdraw(aptFarmId);
        }
    }

    /**
     * @notice Used to emergency withdraw underlying from the AP vault
     * @notice Will fail if emergency mode has not been set on the AP vault
     */
    function emergencyWithdrawFromAutoPool() public onlyRole(GOVERNANCE) {
        totalShares = 0;
        totalAutoPoolShareTokens = 0;
        autoPoolVault.emergencyWithdraw();
    }

    /**
     * @notice Used to emergency withdraw from the AP farm, withdraw underlying from the AP vault, and rescue tokens
     * @notice Will fail if emergency mode has not been set on the vault
     * @param _recipient The address of the receiver
     */
    function emergencyWithdrawAndRescue(address _recipient) external onlyRole(GOVERNANCE) {
        emergencyWithdrawFromFarm();
        emergencyWithdrawFromAutoPool();
        uint256 _amountA = tokenA.balanceOf(address(this));
        uint256 _amountB = tokenB.balanceOf(address(this));
        _rescueTokens(tokenA, _amountA, _recipient, false);
        _rescueTokens(tokenB, _amountB, _recipient, false);
    }

    /**
     * @notice Used to emergency redeem queued withdrawals from AutoPool
     * @param _roundId RoundId to indicate from which round we need to withdraw funds
     */
    function emergencyRedeemQueuedWithdrawal(uint256 _roundId) external onlyRole(GOVERNANCE) {
        autoPoolVault.redeemQueuedWithdrawal(_roundId, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Queues a given product for redemption
     */
    function _queueForRedemption() internal {
        address _productAddress = msg.sender;
        uint256 _productShares = productAPTShare[_productAddress];

        if (_productShares == 0) revert NoShares();
        productAPTShare[_productAddress] = 0;

        uint256 _aptSharesOwnedByProduct = _sharesToTokens(_productShares, totalShares, totalAutoPoolShareTokens);

        // Should pass the shares in `autoPoolTokenDecimals` not in WAD
        uint256 _amountToWithdrawFromVault = _aptSharesOwnedByProduct;

        if (numRewards > 0) {
            APT_FARM.withdraw(aptFarmId, _amountToWithdrawFromVault);
        }

        uint256 _apShareTokensBalanceBefore = autoPoolVault.balanceOf(address(this));

        uint256 _roundId = autoPoolVault.queueWithdrawal(_amountToWithdrawFromVault, address(this));

        uint256 _apShareTokensBalanceAfter = _apShareTokensBalanceBefore - autoPoolVault.balanceOf(address(this));

        /// Derive product details for the current round for redemption.
        DataTypes.Round storage _roundInfo = roundInfo[_roundId];

        /// If no.of products for present round is equal to max iterations, revert
        if (_roundInfo.products.length == maxIterations) revert RoundOccupied();

        uint256 _productSharesForRound =
            _tokenToShares(_apShareTokensBalanceAfter, _roundInfo.totalShares, _roundInfo.totalAutoPoolTokens);

        /// We record round info to iterate through in `redeemTokens()`
        _roundInfo.totalShares += _productSharesForRound;
        _roundInfo.totalAutoPoolTokens += _apShareTokensBalanceAfter;
        _roundInfo.products.push(_productAddress);
        _roundInfo.shares.push(_productSharesForRound);
        if (roundIds.length == 0 || roundIds[roundIds.length - 1] != _roundId) {
            roundIds.push(_roundId);
        }
        /// Update state variables.
        totalShares -= _productShares;
        totalAutoPoolShareTokens -= _apShareTokensBalanceAfter;

        emit RedemptionQueued(_productAddress, _roundId);
    }

    /**
     * @notice Deposits the APT tokens into the farming pool
     * @param _aptAmount Amount of APT tokens to be supplied to the farm
     */
    function _depositAPTToFarm(uint256 _aptAmount) internal {
        if (numRewards > 0 && _aptAmount > 0) {
            IERC20Metadata(autoPoolVault).safeIncreaseAllowance(address(APT_FARM), _aptAmount);

            APT_FARM.deposit(aptFarmId, _aptAmount);

            emit TokensFarmed(_aptAmount);
        }
    }

    function _recompoundRewards() internal {
        uint256 _wavaxBalanceBefore = IERC20Metadata(WAVAX).balanceOf(address(this));
        uint256 _tokenABalanceBefore = tokenA.balanceOf(address(this));
        uint256 _tokenBBalanceBefore = tokenB.balanceOf(address(this));
        (uint256 _reward1, uint256 _reward2) = _harvestRewards();

        if (_reward1 > 0 || _reward2 > 0) {
            _recompoundRewards(_reward1, _reward2, _wavaxBalanceBefore);

            uint256 _tokenAHarvested = tokenA.balanceOf(address(this)) - _tokenABalanceBefore;
            uint256 _tokenBHarvested = tokenB.balanceOf(address(this)) - _tokenBBalanceBefore;

            tokenA.safeIncreaseAllowance(address(autoPoolVault), _tokenAHarvested);
            tokenB.safeIncreaseAllowance(address(autoPoolVault), _tokenBHarvested);

            uint256 _autoPoolShareTokensBefore = autoPoolVault.balanceOf(address(this));
            autoPoolVault.deposit(_tokenAHarvested, _tokenBHarvested);

            uint256 _autoPoolShareTokensReceived = autoPoolVault.balanceOf(address(this)) - _autoPoolShareTokensBefore;

            totalAutoPoolShareTokens += _autoPoolShareTokensReceived;

            _depositAPTToFarm(_autoPoolShareTokensReceived);

            emit RewardsRecompounded(_reward1, _reward2, _tokenAHarvested, _tokenBHarvested);
        }
    }

    /**
     * @notice Harvests the rewards accumulated in the farming pool and recompound it by converting it into LP tokens
     * @return reward1 The amount of rewardTokens1 received from the farm
     * @return reward2 The amount of rewardTokens2 received from the farm
     */
    function _harvestRewards() internal returns (uint256 reward1, uint256 reward2) {
        if (numRewards < 1) return (0, 0);
        uint256 _reward1BalBefore = joeToken.balanceOf(address(this));
        uint256 _reward2BalBefore;
        bool _isDualReward = numRewards > 1;
        /// reward2 exists only if it is a dual reward farm
        if (_isDualReward) {
            if (isReward2Native) {
                _reward2BalBefore = address(this).balance;
            } else {
                _reward2BalBefore = rewardToken2.balanceOf(address(this));
            }
        }

        /// harvest the rewards
        uint256[] memory farmIdArray = new uint256[](1);
        farmIdArray[0] = aptFarmId;
        APT_FARM.harvestRewards(farmIdArray);

        reward1 = joeToken.balanceOf(address(this)) - _reward1BalBefore;

        /// factor-in reward2
        if (_isDualReward) {
            if (isReward2Native) {
                reward2 = address(this).balance - _reward2BalBefore;
            } else {
                reward2 = rewardToken2.balanceOf(address(this)) - _reward2BalBefore;
            }
        }
    }

    /**
     * @notice Used to set allowance and perform a swap based on the given params
     * @param _token The address of the token to be swapped
     * @param _amount  The total amount to be swapped
     * @param _path The path for the swap
     */
    function _increaseAllowanceAndSwap(uint256 _amount, IERC20Metadata _token, address[] memory _path) internal {
        ILBQuoter.Quote memory _quote;

        _quote = lbQuoter.findBestPathFromAmountIn(_path, uint128(_amount));

        _token.safeIncreaseAllowance(address(lbRouter), _amount);

        (bool _validPrice, uint256 _exchangeRate) = _getTokenRate(_path, _amount);

        require(_validPrice, Errors.PFE_RATEDIFF_EXCEEDS_DEVIATION);

        uint256 _fromTokenDecimals = _token.decimals();
        uint256 _toTokenDecimals = IERC20Metadata(_path[_path.length - 1]).decimals();
        uint256 _amountWad = _amount;
        if (_fromTokenDecimals != 18) {
            _amountWad = Helpers.tokenDecimalsToWei(_fromTokenDecimals, _amount);
        }

        uint256 _minOutWithoutSlippage = _amountWad.mulDiv(_exchangeRate, 1e18);
        uint256 _minOut = _minOutWithoutSlippage - _minOutWithoutSlippage.percentMul(slippage / 1e2);

        if (_toTokenDecimals != 18) {
            _minOut = Helpers.weiToTokenDecimals(_toTokenDecimals, _minOut);
        }
        ILBRouter.Path memory _route = ILBRouter.Path(_quote.binSteps, _quote.versions, _quote.route);
        lbRouter.swapExactTokensForTokens(_amount, _minOut, _route, address(this), block.timestamp + 1);
    }

    /**
     * @notice Used to swap tokens and add liquidity for recompounding rewards
     * @param _reward1Harvested Amount of reward1 received from harvesting rewards
     * @param _reward2Harvested Amount of reward2 received from harvesting rewards
     * @param _wavaxBalanceBefore Balance of WAVAX in the contract before harvesting rewards
     */
    function _recompoundRewards(uint256 _reward1Harvested, uint256 _reward2Harvested, uint256 _wavaxBalanceBefore)
        internal
        virtual
    {
        bool _hasNativeReward;

        IERC20Metadata _rewardToken1 = joeToken;
        IERC20Metadata _rewardToken2 = rewardToken2;

        /// If reward1 tokens are  neither tokenA and tokenB, swap all reward1 tokens to the native token
        if (_reward1Harvested > 0) {
            if (address(_rewardToken1) != address(tokenA) && address(_rewardToken1) != address(tokenB)) {
                /// Set _hasNativeReward to true as we are going to swap all reward1 tokens to WAVAX
                _hasNativeReward = true;
                _increaseAllowanceAndSwap(_reward1Harvested, _rewardToken1, joeToNativeSwapPath);
            }
        }

        /// If reward2 is there, it would be either WAVAX, AVAX or other token
        /// if WAVAX, then do nothing, just set `_hasNativeReward` to true, so that we can swap equally to tokenA and tokenB
        /// If AVAX. wrap it to WAVAX then do the same above.
        /// If other token, swap reward 2 accrued to wavax
        if (numRewards > 1 && _reward2Harvested > 0) {
            if (address(_rewardToken2) != address(tokenA) && address(_rewardToken2) != address(tokenB)) {
                if (isReward2Native) {
                    IWETH9(WAVAX).deposit{value: _reward2Harvested}();
                } else {
                    if (address(rewardToken2) != address(WAVAX)) {
                        _increaseAllowanceAndSwap(_reward2Harvested, _rewardToken2, reward2ToNativeSwapPath);
                    }
                }
                _hasNativeReward = true;
            }
        }
        /// If there are native tokens, check if they are srTokens or jrTokens
        /// If they are srTokens, swap half to jrTokens
        /// If they are jrTokens, swap half to srTokens
        /// Else swap it to equal amounts of srTokens and jrTokens
        if (_hasNativeReward) {
            uint256 nativeHalf = (IERC20Metadata(WAVAX).balanceOf(address(this)) - _wavaxBalanceBefore) / 2;
            if (nativeHalf > 0 && (address(tokenA) != address(WAVAX) && address(tokenB) != address(WAVAX))) {
                _increaseAllowanceAndSwap(nativeHalf, IERC20Metadata(WAVAX), nativeToTokenASwapPath);
                _increaseAllowanceAndSwap(nativeHalf, IERC20Metadata(WAVAX), nativeToTokenBSwapPath);
            }
        }
    }

    /**
     * @notice Validates and returns the exchange rate for the given assets from the chainlink oracle and AMM.
     * @dev This is required to prevent oracle manipulation attacks.
     * @param _path The path to get the exchange rate from the AMM (TraderJoe Liquidity Book)
     * @param _amount The amount of tokens to be swapped
     */
    function _getTokenRate(address[] memory _path, uint256 _amount) internal view returns (bool, uint256) {
        uint256 _toTokenIndex = _path.length - 1;
        uint256 _priceAsset1 = structPriceOracle.getAssetPrice(_path[0]);
        uint256 _priceAsset2 = structPriceOracle.getAssetPrice(_path[_toTokenIndex]);
        /// Calculate the exchange rate using the prices from StructPriceOracle (Chainlink price feed)
        uint256 _chainlinkRate = _priceAsset1.mulDiv(Constants.WAD, _priceAsset2);

        if (_amount < 10 ** IERC20Metadata(_path[0]).decimals()) {
            _amount = 10 ** IERC20Metadata(_path[0]).decimals();
        }
        /// Calculate the exchange rate using the Router
        ILBQuoter.Quote memory quote = lbQuoter.findBestPathFromAmountIn(_path, uint128(_amount));

        uint256 _ammRate = Helpers.tokenDecimalsToWei(
            IERC20Metadata(_path[_toTokenIndex]).decimals(), quote.amounts[_toTokenIndex]
        ).mulDiv(Constants.WAD, Helpers.tokenDecimalsToWei(IERC20Metadata(_path[0]).decimals(), _amount));

        /// Check if the relative price diff % is within the MAX_DEVIATION
        /// if yes, return the exchange rate and true flag
        /// if not, return the rate as 0 and false flag
        return Helpers._isWithinBound(_chainlinkRate, _ammRate) ? (true, _ammRate) : (false, 0);
    }

    function _rescueTokens(IERC20Metadata _tokenAddress, uint256 _amount, address _recipient, bool _isNative)
        internal
    {
        if (_isNative) {
            (bool transferResult,) = payable(_recipient).call{value: _amount}("");
            if (transferResult == false) revert NativeTransferFailed();
        } else {
            _tokenAddress.safeTransfer(_recipient, _amount);
        }
    }

    function _updateFarmInfo(address _autoPoolVault) internal {
        if (APT_FARM.hasFarm(_autoPoolVault)) {
            aptFarmId = APT_FARM.vaultFarmId(_autoPoolVault);
            IAPTFarm.FarmInfo memory _farmInfo = APT_FARM.farmInfo(aptFarmId);

            rewardToken2 = address(_farmInfo.rewarder) == address(0)
                ? IERC20Metadata(address(0))
                : IERC20Metadata(address(IRewarder(_farmInfo.rewarder).rewardToken()));

            if (address(_farmInfo.rewarder) == address(0)) {
                numRewards = 1;
            } else {
                numRewards = 2;
                // If rewarder exists and if rewardToken is address(0) then reward2 is native token
                isReward2Native = address(rewardToken2) == address(0) ? true : false;
            }
        } else {
            aptFarmId = type(uint256).max;
            numRewards = 0;
        }
    }
    /*//////////////////////////////////////////////////////////////
                             VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the `roundInfo` for the given round id
     */
    function getRoundInfo(uint256 _roundId) external view returns (DataTypes.Round memory _roundInfo) {
        return roundInfo[_roundId];
    }
}
