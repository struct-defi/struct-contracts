// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External imports
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// Internal imports
import {IGLPManager} from "../../external/gmx/IGLPManager.sol";
import {IGMXRewardRouterV2} from "../../external/gmx/IGMXRewardRouterV2.sol";
import {IGMXVault} from "../../external/gmx/IGMXVault.sol";

import {CustomReentrancyGuard} from "../../utils/CustomReentrancyGuard.sol";
import {GACManaged} from "../common/GACManaged.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {IGMXYieldSource} from "../../interfaces/IGMXYieldSource.sol";
import {IStructPriceOracle} from "../../interfaces/IStructPriceOracle.sol";

import {WadMath} from "../../utils/WadMath.sol";
import {Helpers} from "../libraries/helpers/Helpers.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Constants} from "../libraries/helpers/Constants.sol";

/// @title GMX Yield Source integration contract,
/// @dev This contract inherits GACManaged which extends Pausable also uses the GAC for access control
/// @notice Yield source for the FEYGMXProduct that generates yield via GMX protocol
contract GMXYieldSource is IGMXYieldSource, GACManaged, CustomReentrancyGuard {
    using SafeERC20 for IERC20Metadata;
    using WadMath for uint256;

    /*//////////////////////////////////////////////////////////////
                         GMX INFO STORAGE
    //////////////////////////////////////////////////////////////*/

    IGMXRewardRouterV2 public constant GLP_REWARD_ROUTERV2 =
        IGMXRewardRouterV2(0xB70B91CE0771d3f4c81D87660f71Da31d48eB3B3);

    IGLPManager public constant GLP_MANAGER = IGLPManager(0xD152c7F25db7F4B95b7658323c5F33d176818EE4);

    /// This is used for Harvesting rewards
    IGMXRewardRouterV2 public constant GMX_REWARD_ROUTER =
        IGMXRewardRouterV2(0x82147C5A7E850eA4E28155DF107F2590fD4ba327);

    IGMXVault public constant VAULT = IGMXVault(0x9ab2De34A33fB459b538c43f251eB825645e8595);

    IERC20Metadata public constant FSGLP = IERC20Metadata(0x9e295B5B976a184B14aD8cd72413aD846C299660);

    uint256 public constant BPS_MAX = 10000;

    /*//////////////////////////////////////////////////////////////
                        PRODUCT INFO STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Used to map the product address with the related info
    mapping(address => DataTypes.FEYGMXProductInfo) public productInfo;

    /*//////////////////////////////////////////////////////////////
                        OTHER INFO STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Address of the FEYGMXFactory
    address public immutable feyFactory;

    IERC20Metadata public constant WAVAX = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    /// @notice This will be the shares allocated to the first product
    /// @dev Required to prevent share manipulation.
    uint256 public constant INITIAL_SHARES = 10 ** 8;

    /// @notice The maximum amount of slippage allowed when buying/selling GLP tokens
    uint256 public slippage = 30;

    /// @notice the total shares owned by all products that use this contract
    uint256 public totalShares;

    /// @notice the aggregated sum of fsGLP tokens in this contract
    /// @dev we track it manually to avoid inflation attacks.
    uint256 public fsGlpTokensTotal;

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _feyFactory Address of the FEYFactory contract
     * @param _globalAccessControl Address of the GlobalAccessControl contract
     */
    constructor(address _feyFactory, IGAC _globalAccessControl) {
        __GACManaged_init(_globalAccessControl);
        feyFactory = _feyFactory;
    }

    /*//////////////////////////////////////////////////////////////
                        YIELDSOURCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IGMXYieldSource
     * @dev Only PRODUCT contracts can call this method
     */
    function supplyTokens(uint256 _amountAIn, uint256 _amountBIn)
        external
        override
        gacPausable
        nonReentrant
        onlyRole(PRODUCT)
        returns (uint256 _amountAInWei, uint256 _amountBInWei)
    {
        DataTypes.FEYGMXProductInfo storage _productInfo = productInfo[_msgSender()];

        if (_productInfo.shares > 0) revert AlreadySupplied();

        _recompoundRewards();

        uint256 _fsGlpBalanceBefore = _fsGlpTokenBalance();

        (_amountAInWei, _amountBInWei) = _supplyLiquidity(_amountAIn, _amountBIn, _productInfo);

        uint256 _fsGlpBalanceAfter = _fsGlpTokenBalance();

        uint256 _fsGlpTokensAdded = _fsGlpBalanceAfter - _fsGlpBalanceBefore;

        uint256 _shares = _tokenToShares(_fsGlpTokensAdded, fsGlpTokensTotal);

        if (_shares < 1) revert ZeroShares();

        /// Record the product's share of the LP Token
        _productInfo.shares = _shares;
        _productInfo.fsGLPReceived = _fsGlpTokensAdded;

        /// Update total shares
        totalShares += _shares;
        /// Update fsGLPTotal
        fsGlpTokensTotal += _fsGlpTokensAdded;

        emit TokensSupplied(_amountAInWei, _amountBInWei, _fsGlpTokensAdded);
    }

    /**
     * @inheritdoc IGMXYieldSource
     * @dev Only PRODUCT contracts can call this method
     */
    function redeemTokens(uint256 _expectedSrAmount)
        external
        override
        gacPausable
        nonReentrant
        onlyRole(PRODUCT)
        returns (uint256 _amountARedeemed, uint256 _amountBRedeemed)
    {
        DataTypes.FEYGMXProductInfo memory _productInfo = productInfo[_msgSender()];

        if (_productInfo.shares == 0) revert NoShares(_msgSender());

        _recompoundRewards();

        uint256 _productShares = _productInfo.shares;
        uint256 _fsGlpTokenAmount = _sharesToTokens(_productShares, fsGlpTokensTotal);

        if (_fsGlpTokenAmount == 0) revert ZeroShares();

        uint256 _fsGlpBalanceBefore = _fsGlpTokenBalance();

        uint256 _pricePerTokenA = VAULT.getMaxPrice(_productInfo.tokenA) / Constants.GMX_PRICE_DIVISOR;

        uint256 _fsGlpToRedeemAsTokenA = (_expectedSrAmount * _pricePerTokenA) / _getGLPPrice(false);
        // Initialize variable to store fsGlp reserved for senior tranche
        uint256 _fsGlpReservedForSr;
        // Check if tokenA and tokenB are the same or if the product's fsGlpTokenAmount
        // is less than or equal to the amount to redeem as tokenA
        if (_productInfo.sameToken || _fsGlpTokenAmount <= _fsGlpToRedeemAsTokenA) {
            // Set the fsGlp reserved for senior tranche to the amount to redeem as tokenA
            _fsGlpReservedForSr = _fsGlpToRedeemAsTokenA;
            // Update the amount to redeem as tokenA to the product's fsGlpTokenAmount
            _fsGlpToRedeemAsTokenA = _fsGlpTokenAmount;
        } else {
            /// Junior tranche (TokenB) should absorb the withdrawal fee
            _fsGlpToRedeemAsTokenA = _fsGlpToRedeemAsTokenA * BPS_MAX
                / (BPS_MAX - _getFeeBps(_fsGlpToRedeemAsTokenA, false, _productInfo.tokenA));
        }
        // Calculate the minimum token amount out for tokenA
        uint256 _minOut =
            _calculateTokenAmountOutForFsGLP(_fsGlpToRedeemAsTokenA, _productInfo.tokenA, _productInfo.tokenADecimals);
        // Unstake and redeem GLP for tokenA
        _amountARedeemed =
            GLP_REWARD_ROUTERV2.unstakeAndRedeemGlp(_productInfo.tokenA, _fsGlpToRedeemAsTokenA, _minOut, _msgSender());

        if (!_productInfo.sameToken) {
            if (_fsGlpTokenAmount > _fsGlpToRedeemAsTokenA) {
                uint256 _fsGlpToRedeemAsTokenB = _fsGlpTokenAmount - _fsGlpToRedeemAsTokenA;
                // Calculate the minimum token amount out for tokenB
                _minOut = _calculateTokenAmountOutForFsGLP(
                    _fsGlpToRedeemAsTokenB, _productInfo.tokenB, _productInfo.tokenBDecimals
                );
                // Unstake and redeem GLP for tokenB
                _amountBRedeemed = GLP_REWARD_ROUTERV2.unstakeAndRedeemGlp(
                    _productInfo.tokenB, _fsGlpToRedeemAsTokenB, _minOut, _msgSender()
                );
            }
            // If tokenA is equal to tokenB and the product's fsGlpTokenAmount is
            // greater than the reserved amount for senior tranche
        } else if (_fsGlpTokenAmount > _fsGlpReservedForSr) {
            // Calculate the expected senior amount in token decimals
            uint256 _expectedSrAmountInTokenDecimals =
                Helpers.weiToTokenDecimals(_productInfo.tokenADecimals, _expectedSrAmount);
            // Set amountBRedeemed as the difference between amountARedeemed and expected senior amount
            _amountBRedeemed = _amountARedeemed - _expectedSrAmountInTokenDecimals;
            // Set amountARedeemed as the expected senior amount
            _amountARedeemed = _expectedSrAmountInTokenDecimals;
        }

        totalShares -= _productShares;
        uint256 _fsGlpTokensRemoved = _fsGlpBalanceBefore - _fsGlpTokenBalance();
        fsGlpTokensTotal -= _fsGlpTokensRemoved;
        productInfo[_msgSender()].shares = 0;

        emit TokensRedeemed(_amountARedeemed, _amountBRedeemed);
    }

    /// @inheritdoc IGMXYieldSource
    function recompoundRewards() public override gacPausable onlyRole(KEEPER) {
        _recompoundRewards();
    }

    /// @notice Used by the Governance to incentivize products by distributing WAVAX as rewards
    /// @dev Any wAVAX that is in the balance of the contract before this function is called,
    ///      will be converted into GLP tokens and assigned as new shares to the product
    ///      that we would like to incentivize or subsidize
    /// @param _products Array of product addresses that we wanna distrubute rewards to
    /// @param _amount The amount of wAVAX to be distributed.
    /// @custom:note wAVAX should be sent to the contract before calling this method.
    function addRewards(address[] memory _products, uint256 _amount) external onlyRole(GOVERNANCE) {
        uint256 _wavaxBalance = WAVAX.balanceOf(address(this));

        if (_wavaxBalance < _amount) revert InsufficientRewards(_wavaxBalance, _amount);

        WAVAX.approve(address(GLP_MANAGER), _amount);

        uint256 _fsGlpBalanceBefore = _fsGlpTokenBalance();

        GLP_REWARD_ROUTERV2.mintAndStakeGlp(address(WAVAX), _amount, 0, 0); // ignore slippage

        uint256 _fsGlpReceived = _fsGlpTokenBalance() - _fsGlpBalanceBefore;

        uint256 _shares = _tokenToShares(_fsGlpReceived, fsGlpTokensTotal);

        if (_shares < 1) revert ZeroShares();

        uint256 _sharesPerProduct = _shares / _products.length;

        for (uint256 i = 0; i < _products.length; i++) {
            address _productAddress = _products[i];
            DataTypes.FEYGMXProductInfo storage _productInfo = productInfo[_productAddress];

            if (_productInfo.shares <= 0) {
                revert NoShares(_productAddress);
            }
            /// Update product shares
            _productInfo.shares += _sharesPerProduct;

            emit RewardsAdded(_productAddress);
        }

        /// Update total shares
        totalShares += _shares;

        fsGlpTokensTotal += _fsGlpReceived;
    }

    /*//////////////////////////////////////////////////////////////
                             PRIVATE METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the amounts in the token decimals to be passed to the `addLiquidity()`
     * @param _amountA The amount to be supplied for tokenA in 18 decimals
     * @param _amountB The amount to be supplied for tokenB in 18 decimals
     * @param _productInfo The product info
     */
    function _supplyLiquidity(uint256 _amountA, uint256 _amountB, DataTypes.FEYGMXProductInfo storage _productInfo)
        internal
        returns (uint256 _amountAInWei, uint256 _amountBInWei)
    {
        address _product = _msgSender();

        if (_productInfo.sameToken) {
            _amountA += _amountB;
        }

        /// Pull the tokens from the product contract
        IERC20Metadata(_productInfo.tokenA).safeTransferFrom(_product, address(this), _amountA);

        /// Increase allowance for the GLP_MANAGER contract
        IERC20Metadata(_productInfo.tokenA).safeIncreaseAllowance(address(GLP_MANAGER), _amountA);

        uint256 _priceTokenA = VAULT.getMinPrice(_productInfo.tokenA) / Constants.GMX_PRICE_DIVISOR;

        /// Buy GLP with TokenA
        _amountAInWei = Helpers.tokenDecimalsToWei(_productInfo.tokenADecimals, _amountA);
        uint256 _expectedGLPAmountForToken = _calculateGLPAmountOutForToken(_amountAInWei, _priceTokenA, true);
        uint256 _feeBps = _getFeeBps(_expectedGLPAmountForToken, true, _productInfo.tokenA);

        GLP_REWARD_ROUTERV2.mintAndStakeGlp(
            _productInfo.tokenA, _amountA, 0, ((BPS_MAX - (slippage + _feeBps)) * _expectedGLPAmountForToken) / BPS_MAX
        );

        _amountBInWei = Helpers.tokenDecimalsToWei(_productInfo.tokenBDecimals, _amountB);

        if (!_productInfo.sameToken) {
            /// Buy GLP with TokenB
            IERC20Metadata(_productInfo.tokenB).safeTransferFrom(_product, address(this), _amountB);
            IERC20Metadata(_productInfo.tokenB).safeIncreaseAllowance(address(GLP_MANAGER), _amountB);

            uint256 _priceTokenB = VAULT.getMinPrice(_productInfo.tokenB) / Constants.GMX_PRICE_DIVISOR;

            _expectedGLPAmountForToken = _calculateGLPAmountOutForToken(_amountBInWei, _priceTokenB, true);
            _feeBps = _getFeeBps(_expectedGLPAmountForToken, true, _productInfo.tokenB);

            GLP_REWARD_ROUTERV2.mintAndStakeGlp(
                _productInfo.tokenB,
                _amountB,
                0,
                ((BPS_MAX - (slippage + _feeBps)) * _expectedGLPAmountForToken) / BPS_MAX
            );
        } else {
            // deduct amountB from amountA to return the amount supplied by the tokenA tranche
            _amountAInWei = Helpers.tokenDecimalsToWei(_productInfo.tokenADecimals, _amountA - _amountB);
        }
    }

    function _recompoundRewards() internal {
        uint256 _wavaxBalanceBefore = WAVAX.balanceOf(address(this));

        /// Harvest only wAVAX rewards as there'll be neither esGMX nor GMX rewards.
        GMX_REWARD_ROUTER.handleRewards(false, false, false, false, true, true, false);

        uint256 _rewardsHarvested = WAVAX.balanceOf(address(this)) - _wavaxBalanceBefore;
        if (_rewardsHarvested == 0) return;

        WAVAX.approve(address(GLP_MANAGER), _rewardsHarvested);

        uint256 _fsGlpBalanceBefore = _fsGlpTokenBalance();

        GLP_REWARD_ROUTERV2.mintAndStakeGlp(address(WAVAX), _rewardsHarvested, 0, 0); // ignore slippage

        uint256 _fsGlpReceived = _fsGlpTokenBalance() - _fsGlpBalanceBefore;

        fsGlpTokensTotal += _fsGlpReceived;

        emit RewardsRecompounded();
    }

    /**
     * @notice Calculates the number of shares that should be mint or burned when a product deposit or withdraw
     * @param _tokens Amount of tokens
     * @param _fsGlpTotal Total fsGLP tokens in this contract
     * @return _shares Number of shares
     */
    function _tokenToShares(uint256 _tokens, uint256 _fsGlpTotal) internal view returns (uint256 _shares) {
        if (totalShares == 0 && _tokens > 0) {
            if (_tokens < INITIAL_SHARES) {
                _shares = INITIAL_SHARES;
            } else {
                _shares = _tokens;
            }
        } else {
            _shares = _tokens.mulDiv(totalShares, _fsGlpTotal);
        }
    }

    /**
     * @notice Calculates the number of tokens that should be mint or burned when a product deposit or withdraw
     * @param _shares Amount of shares for given no.of tokens
     * @param _fsGlpTotal Total fsGLP tokens in the yield source
     * @return _tokens Number of tokens
     */
    function _sharesToTokens(uint256 _shares, uint256 _fsGlpTotal) internal view returns (uint256 _tokens) {
        if (totalShares == 0) {
            _tokens = 0;
        } else {
            _tokens = _shares.mulDiv(_fsGlpTotal, totalShares);
        }
    }

    /// @notice Returns the total balance of `fsGLP` tokens of this contract
    function _fsGlpTokenBalance() internal view returns (uint256) {
        return FSGLP.balanceOf(address(this));
    }

    /// @notice Returns the GLP buy price
    function _getGLPPrice(bool _maximize) public view returns (uint256 price) {
        price = GLP_MANAGER.getPrice(_maximize) / Constants.GMX_PRICE_DIVISOR;
    }

    /**
     * @notice Returns the `minOut` value for buying GLP with the given token
     * @param _amount The token amount used to purchase the GLP tokens
     * @param _tokenPriceUSD The price of the token in USD
     * @param _maximize Flag indicating buy or sell action
     * @return amountOut The expected fsGLP to be recieved
     */
    function _calculateGLPAmountOutForToken(uint256 _amount, uint256 _tokenPriceUSD, bool _maximize)
        internal
        view
        returns (uint256 amountOut)
    {
        amountOut = _amount.mulDiv(_tokenPriceUSD, _getGLPPrice(_maximize));
    }

    /**
     * @notice Returns the `minOut` value for selling GLP for the given token
     * @param _amountfsGlp The amount of fsGlp tokens to be redeemed
     * @param _token The address of the token
     * @return amountOut The expected tokens to be recieved
     */
    function _calculateTokenAmountOutForFsGLP(uint256 _amountfsGlp, address _token, uint256 _tokenDecimals)
        internal
        view
        returns (uint256 amountOut)
    {
        uint256 glpPrice = _getGLPPrice(false);
        uint256 tokenOutPrice = VAULT.getMaxPrice(_token) / Constants.GMX_PRICE_DIVISOR;

        amountOut = (
            (BPS_MAX - (slippage + _getFeeBps(_amountfsGlp, false, _token)))
                * ((_amountfsGlp * glpPrice) / tokenOutPrice)
        ) / BPS_MAX;

        amountOut = Helpers.weiToTokenDecimals(_tokenDecimals, amountOut);
    }

    /**
     * @notice Returns the feeBps to buy/sell GLP tokens
     * @param _amountfsGLP The amount of fsGLP tokens to be sold
     * @param _maximize A flag indicating if we are gonna buy or sell
     * @param _token Address of the token to be bought with or sold for
     * @return feeBps The buy/sell fee in basis points
     */
    function _getFeeBps(uint256 _amountfsGLP, bool _maximize, address _token) internal view returns (uint256 feeBps) {
        uint256 taxFee = VAULT.taxBasisPoints();
        uint256 mintBurnFee = VAULT.mintBurnFeeBasisPoints();
        uint256 usdgDelta = (_amountfsGLP * GLP_MANAGER.getPrice(_maximize)) / 1e30;
        feeBps = VAULT.getFeeBasisPoints(_token, usdgDelta, mintBurnFee, taxFee, _maximize);
    }

    function getFEYGMXProductInfo(address _productAddress) public view returns (DataTypes.FEYGMXProductInfo memory) {
        return productInfo[_productAddress];
    }

    function setFEYGMXProductInfo(address _productAddress, DataTypes.FEYGMXProductInfo memory _productInfo)
        external
        onlyRole(FACTORY)
    {
        productInfo[_productAddress] = _productInfo;
    }
}
