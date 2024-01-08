// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "../../../external/IWETH9.sol";
import {IGMXVault} from "../../../external/gmx/IGMXVault.sol";
import {IFastPriceFeed} from "../../../external/gmx/IFastPriceFeed.sol";
import {IVaultPriceFeed} from "../../../external/gmx/IVaultPriceFeed.sol";

/// Internal Imports
import {CustomReentrancyGuard} from "../../../utils/CustomReentrancyGuard.sol";
import {TraderJoeLPAdapter} from "../../adapters/TraderJoeLPAdapter.sol";
import {ISPToken} from "../../../interfaces/ISPToken.sol";
import {IGMXFEYProduct} from "../../../interfaces/IGMXFEYProduct.sol";
import {IStructPriceOracle} from "../../../interfaces/IStructPriceOracle.sol";
import {IDistributionManager} from "../../../interfaces/IDistributionManager.sol";

import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {Helpers} from "../../libraries/helpers/Helpers.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";
import {Errors} from "../../libraries/helpers/Errors.sol";
import {Validation} from "../../libraries/logic/Validation.sol";
import {GACManaged} from "../../common/GACManaged.sol";
import {IGAC} from "../../../interfaces/IGAC.sol";
import {WadMath} from "../../../utils/WadMath.sol";
import {IGMXYieldSource} from "../../../interfaces/IGMXYieldSource.sol";
import {FEYProduct} from "../FEYProduct.sol";

/**
 * @title Fixed and Enhanced Yield GMX Product contract
 * @notice Main point of interaction with the FEY product contract
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Claim Excess
 *
 * @author Struct Finance
 */
contract FEYGMXProduct is FEYProduct, TraderJoeLPAdapter {
    using SafeERC20 for IERC20Metadata;
    using WadMath for uint256;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    IGMXVault public constant VAULT = IGMXVault(0x9ab2De34A33fB459b538c43f251eB825645e8595);
    IVaultPriceFeed public constant VAULT_PRICE_FEED = IVaultPriceFeed(0x27e99387af40e5CA9CE21418552f15F02C8C57E7);
    IFastPriceFeed public constant FAST_PRICE_FEED = IFastPriceFeed(0xE547CaDbe081749e5b3DC53CB792DfaEA2D02fD2);

    /// @dev The address of the GMXYieldSource contract
    IGMXYieldSource public yieldSource;

    /// @dev Swap paths
    address[] internal seniorToNative;
    address[] internal juniorToNative;

    /**
     * @notice Initializes the Product based on the given parameters
     * @dev It should be called only once
     * @param _initConfig Configuration of the tranches and product config
     * @param _structPriceOracle The address of the struct price oracle
     * @param _spToken Address of the Struct SP Token
     * @param _globalAccessControl Address of the StructGAC contract
     * @param _distributionManager Address of the distribution manager contract
     * @param _yieldSource Address of the YieldSource contract
     */
    function initialize(
        DataTypes.InitConfigParam calldata _initConfig,
        IStructPriceOracle _structPriceOracle,
        ISPToken _spToken,
        IGAC _globalAccessControl,
        IDistributionManager _distributionManager,
        address _yieldSource,
        address payable _nativeToken
    ) external override {
        require(!isInitialized, Errors.ACE_INITIALIZER);
        __GACManaged_init(_globalAccessControl);

        productFactory = _msgSender();

        trancheConfig[DataTypes.Tranche.Senior] = _initConfig.configTrancheSr;
        trancheConfig[DataTypes.Tranche.Junior] = _initConfig.configTrancheJr;
        productConfig = _initConfig.productConfig;
        nativeToken = _nativeToken;

        structPriceOracle = _structPriceOracle;
        distributionManager = _distributionManager;
        spToken = _spToken;
        yieldSource = IGMXYieldSource(_yieldSource);

        slippage = Constants.DEFAULT_SLIPPAGE;
        _srDecimals = _initConfig.configTrancheSr.decimals;
        _jrDecimals = _initConfig.configTrancheJr.decimals;

        /// @dev Construct swap path array
        address[] memory _seniorToNative = new address[](2);
        _seniorToNative[0] = address(_initConfig.configTrancheSr.tokenAddress);
        _seniorToNative[1] = nativeToken;
        seniorToNative = _seniorToNative;

        address[] memory _juniorToNative = new address[](2);
        _juniorToNative[0] = address(_initConfig.configTrancheJr.tokenAddress);
        _juniorToNative[1] = nativeToken;
        juniorToNative = _juniorToNative;

        isInitialized = true;
    }

    /**
     * @notice Method will deposit the funds into the relevant LP.
     * @dev The method will keep track of the total amount that was deposited into each tranche.
     * @dev Swaps will be made to balance out both the sides before adding liquidity
     */
    function invest() external override nonReentrant gacPausable {
        uint256 _srTotal = trancheInfo[DataTypes.Tranche.Senior].tokensDeposited;
        uint256 _jrTotal = trancheInfo[DataTypes.Tranche.Junior].tokensDeposited;
        Validation.validateInvest(
            productConfig.startTimeTranche,
            currentState,
            trancheConfig[DataTypes.Tranche.Senior].capacity,
            trancheConfig[DataTypes.Tranche.Junior].capacity,
            _srTotal,
            _jrTotal
        );

        if (_srTotal == 0 || _jrTotal == 0) {
            trancheInfo[DataTypes.Tranche.Senior].tokensExcess = _srTotal;
            trancheInfo[DataTypes.Tranche.Junior].tokensExcess = _jrTotal;
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable = 0;
            trancheInfo[DataTypes.Tranche.Junior].tokensInvestable = 0;
            // TODO: Add a new State?
            currentState = DataTypes.State.WITHDRAWN;
            /// @dev Events to transition product state in the subgraph
            emit Invested(0, 0, 0, 0);
            emit StatusUpdated(DataTypes.State.WITHDRAWN);
            emit RemovedFundsFromLP(0, 0, _msgSender());
            return;
        }

        uint256 _jrToSrRate;
        uint256 _srToJrRate;

        /// If both the tranches are using the same token, then the rate will be 1:1
        if (
            trancheConfig[DataTypes.Tranche.Senior].tokenAddress == trancheConfig[DataTypes.Tranche.Junior].tokenAddress
        ) {
            _jrToSrRate = Constants.WAD;
            _srToJrRate = _jrToSrRate;
        } else {
            /// If the tranches are using different tokens, the rate will be calculated
            /// using the ratio of the min prices of the tokens in the vault
            _jrToSrRate = getTokenRate(DataTypes.Tranche.Senior);
            _srToJrRate = getTokenRate(DataTypes.Tranche.Junior);
        }

        uint256 _investedSr;
        uint256 _investedJr;

        /// Check if total deposits in the junior tranche are within the notional value limits,
        /// i.e. the min and max allowable delta between the two tranches, by comparing it with
        /// the min and max allowable value of the senior tranche in terms of junior tokens.
        /// If so, there will be no excess

        uint256 notionalMinJr = productConfig.leverageThresholdMax * _srTotal.wadMul(_jrToSrRate);
        uint256 notionalMaxJr = productConfig.leverageThresholdMin * _srTotal.wadMul(_jrToSrRate);

        if (
            (_jrTotal * Constants.DECIMAL_FACTOR >= notionalMinJr)
                && (_jrTotal * Constants.DECIMAL_FACTOR <= notionalMaxJr)
        ) {
            trancheInfo[DataTypes.Tranche.Junior].tokensInvestable = _jrTotal;
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable = _srTotal;
            (_investedSr, _investedJr) = _depositToLP(_srTotal, _jrTotal);
        } else if (
            /// Check if the value in the junior tranche is below the notional minimum limit (much less than value in senior tranche)
            /// If so, calculate the amount of excess senior tranche tokens and update state variables
            _jrTotal * Constants.DECIMAL_FACTOR < (notionalMinJr)
        ) {
            uint256 _investableSrTokens =
                (_jrTotal.wadMul(_srToJrRate) * Constants.DECIMAL_FACTOR) / (productConfig.leverageThresholdMax);

            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable = _investableSrTokens;
            trancheInfo[DataTypes.Tranche.Junior].tokensInvestable = _jrTotal;
            trancheInfo[DataTypes.Tranche.Senior].tokensExcess = _srTotal - _investableSrTokens;
            (_investedSr, _investedJr) = _depositToLP(_investableSrTokens, _jrTotal);
        } else {
            /// Else, value in the junior tranche is above the notional maximum limit (much greater than value in senior tranche)
            /// Calculate the amount of excess junior tranche tokens and update state variables
            uint256 _investableJrTokens = notionalMaxJr / Constants.DECIMAL_FACTOR;

            trancheInfo[DataTypes.Tranche.Junior].tokensInvestable = _investableJrTokens;
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable = _srTotal;
            trancheInfo[DataTypes.Tranche.Junior].tokensExcess = _jrTotal - _investableJrTokens;
            (_investedSr, _investedJr) = _depositToLP(_srTotal, _investableJrTokens);
        }

        /// Update the final amount of tokens invested into each tranche
        trancheInfo[DataTypes.Tranche.Senior].tokensInvested = _investedSr;
        trancheInfo[DataTypes.Tranche.Junior].tokensInvested = _investedJr;

        emit Invested(
            _investedSr,
            _investedJr,
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable,
            trancheInfo[DataTypes.Tranche.Junior].tokensInvestable
        );
    }

    /**
     * @notice Used to update the slippage
     * @param _newSlippage The new slippage value to be updated
     */
    function setSlippage(uint256 _newSlippage) external onlyRole(GOVERNANCE) {
        require(_newSlippage < Constants.MAX_SLIPPAGE, Errors.VE_INVALID_SLIPPAGE);
        slippage = _newSlippage;
        emit SlippageUpdated(_newSlippage);
    }

    /**
     * @notice Returns the rate of the tranche token
     * @param _tranche The tranche id for which the token rate should be fetched.
     * @return uint256 - GMX rate of the given _tranche token against the other tranche token
     */
    function getTokenRate(DataTypes.Tranche _tranche) public view returns (uint256) {
        (bool _isPriceValidSr, uint256 _priceTokenSr) =
            _getTokenPrice(address(trancheConfig[DataTypes.Tranche.Senior].tokenAddress));
        require(_isPriceValidSr, Errors.PFE_INVALID_SR_PRICE);
        _priceTokenSr = _priceTokenSr / Constants.GMX_PRICE_DIVISOR;

        (bool _isPriceValidJr, uint256 _priceTokenJr) =
            _getTokenPrice(address(trancheConfig[DataTypes.Tranche.Junior].tokenAddress));
        require(_isPriceValidJr, Errors.PFE_INVALID_JR_PRICE);
        _priceTokenJr = _priceTokenJr / Constants.GMX_PRICE_DIVISOR;

        if (_tranche == DataTypes.Tranche.Senior) {
            return _priceTokenSr.mulDiv(Constants.WAD, _priceTokenJr);
        } else {
            return _priceTokenJr.mulDiv(Constants.WAD, _priceTokenSr);
        }
    }

    function _getTokenPrice(address _token) private view returns (bool, uint256) {
        bool _isPriceValid = true;
        uint256 _fastPrice = FAST_PRICE_FEED.prices(_token);
        uint256 _primaryPrice = VAULT_PRICE_FEED.getLatestPrimaryPrice(_token);
        // Chainlink price is in 8 decimals while _fastPrice is 30 decimals
        uint256 _priceDecimals = VAULT_PRICE_FEED.priceDecimals(_token);
        _primaryPrice = _primaryPrice * 10 ** (30 - _priceDecimals);
        /// _fastPrice does not exist for USDC
        if (_fastPrice == 0) {
            /// check that the the fast price feed does not have a price for this token
            (, uint256 _lastUpdateTime,,) = FAST_PRICE_FEED.getPriceData(_token);
            if (_lastUpdateTime != 0) {
                _isPriceValid = false;
            }
            return (_isPriceValid, _primaryPrice);
        }
        /// check that the price deviation is within the allowed range
        uint256 _diffBasisPoints;
        /// set _priceDivisor to the larger of the two prices
        uint256 _priceDivisor;
        if (_primaryPrice > _fastPrice) {
            _diffBasisPoints = _primaryPrice - _fastPrice;
            _priceDivisor = _primaryPrice;
        } else {
            _diffBasisPoints = _fastPrice - _primaryPrice;
            _priceDivisor = _fastPrice;
        }

        _diffBasisPoints = _diffBasisPoints.mulDiv(BASIS_POINTS_DIVISOR, _priceDivisor);
        if (_diffBasisPoints > Constants.MAX_DEVIATION / 100) {
            _isPriceValid = false;
        }

        return (_isPriceValid, _primaryPrice);
    }

    /**
     * @notice Adds liquidity to the AMM pool
     * @param _tokensInvestableSr Senior tokens eligible for investment to the pool
     * @param _tokensInvestableJr Junior tokens eligible for investment to the pool
     * @return _seniorTokensSupplied Senior tranche tokens invested
     * @return _juniorTokensSupplied Junior tranche tokens invested
     */
    function _depositToLP(uint256 _tokensInvestableSr, uint256 _tokensInvestableJr)
        private
        returns (uint256 _seniorTokensSupplied, uint256 _juniorTokensSupplied)
    {
        currentState = DataTypes.State.INVESTED;
        emit StatusUpdated(DataTypes.State.INVESTED);

        uint256 _tokensInvestableSrInTokenDecimals = Helpers.weiToTokenDecimals(_srDecimals, _tokensInvestableSr);
        uint256 _tokensInvestableJrInTokenDecimals = Helpers.weiToTokenDecimals(_jrDecimals, _tokensInvestableJr);

        /// Increase allowance
        trancheConfig[DataTypes.Tranche.Senior].tokenAddress.safeIncreaseAllowance(
            address(yieldSource), _tokensInvestableSrInTokenDecimals
        );
        trancheConfig[DataTypes.Tranche.Junior].tokenAddress.safeIncreaseAllowance(
            address(yieldSource), _tokensInvestableJrInTokenDecimals
        );
        (_seniorTokensSupplied, _juniorTokensSupplied) =
            yieldSource.supplyTokens(_tokensInvestableSrInTokenDecimals, _tokensInvestableJrInTokenDecimals);
    }

    /**
     * @notice Method withdraws the product's investments from the LP and charges and sends fees to the Distribution Manager.
     */
    function removeFundsFromLP() external override nonReentrant gacPausable {
        Validation.validateRemoveFunds(productConfig.endTimeTranche, currentState);

        currentState = DataTypes.State.WITHDRAWN;

        uint256 _trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        /// Calculate the amount of senior tokens the senior tranche investors expect at maturity
        /// The simplified formula is: (tokensInvestable * (1 + fixedRate * trancheDuration / 1 year))
        uint256 _srFrFactor = (
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable * Constants.YEAR_IN_SECONDS
                + trancheInfo[DataTypes.Tranche.Senior].tokensInvestable * productConfig.fixedRate * _trancheDuration
                    / Constants.DECIMAL_FACTOR
        ) / Constants.YEAR_IN_SECONDS;

        /// pass the srFrFactor to the yieldSource to calculate the amount of tokens to redeem for each tranche
        /// unlike TJ product contract, the GMX product contract allocates the tokens to the tranches during redemption
        (uint256 _receivedSr, uint256 _receivedJr) = yieldSource.redeemTokens(_srFrFactor);

        _receivedSr = Helpers.tokenDecimalsToWei(_srDecimals, _receivedSr);
        _receivedJr = Helpers.tokenDecimalsToWei(_jrDecimals, _receivedJr);

        trancheInfo[DataTypes.Tranche.Senior].tokensReceivedFromLP = _receivedSr;
        trancheInfo[DataTypes.Tranche.Junior].tokensReceivedFromLP = _receivedJr;

        _chargeFee(_receivedSr, _receivedJr);

        /// Capture tokens at maturity
        trancheInfo[DataTypes.Tranche.Senior].tokensAtMaturity = _receivedSr - feeTotalSr;
        trancheInfo[DataTypes.Tranche.Junior].tokensAtMaturity = _receivedJr - feeTotalJr;

        emit StatusUpdated(DataTypes.State.WITHDRAWN);

        emit RemovedFundsFromLP(
            trancheInfo[DataTypes.Tranche.Senior].tokensAtMaturity,
            trancheInfo[DataTypes.Tranche.Junior].tokensAtMaturity,
            _msgSender()
        );
    }

    /**
     * @notice Used to transfer fee when the product is matured
     * @param _receivedSr Senior tokens received from pool
     * @param _receivedJr Junior tokens received from pool
     */
    function _chargeFee(uint256 _receivedSr, uint256 _receivedJr) private {
        DataTypes.TrancheInfo storage _trancheInfoSr = trancheInfo[DataTypes.Tranche.Senior];
        DataTypes.TrancheInfo storage _trancheInfoJr = trancheInfo[DataTypes.Tranche.Junior];

        (feeTotalSr, feeTotalJr) = Helpers.calculateFees(
            _trancheInfoSr.tokensInvestable, _receivedSr, _trancheInfoJr.tokensInvestable, _receivedJr, productConfig
        );
        if (feeTotalSr > 0 || feeTotalJr > 0) {
            /// Get nativeToken balance of receiver before sending it fees
            uint256 _receiverNativeBalanceBefore =
                Helpers._getTokenBalance(IERC20Metadata(nativeToken), address(distributionManager));

            Helpers.swapAndSendFeeToReceiver(
                joeRouter, feeTotalSr, feeTotalJr, seniorToNative, juniorToNative, address(distributionManager)
            );

            /// Get nativeToken balance of receiver after sending it fees
            uint256 _receiverNativeBalanceAfter =
                Helpers._getTokenBalance(IERC20Metadata(nativeToken), address(distributionManager));
            /// Set the difference as the _feeToQueue
            uint256 _feeToQueue = _receiverNativeBalanceAfter - _receiverNativeBalanceBefore;

            distributionManager.queueFees(_feeToQueue);
        }
    }
}
