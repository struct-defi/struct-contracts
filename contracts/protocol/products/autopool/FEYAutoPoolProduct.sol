// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILBQuoter} from "../../../external/traderjoe/ILBQuoter.sol";

/// Internal Imports
import {TraderJoeLPAdapter} from "../../adapters/TraderJoeLPAdapter.sol";
import {ISPToken} from "../../../interfaces/ISPToken.sol";
import {IStructPriceOracle} from "../../../interfaces/IStructPriceOracle.sol";
import {IDistributionManager} from "../../../interfaces/IDistributionManager.sol";
import {IAutoPoolVault} from "../../../external/traderjoe/IAutoPoolVault.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {Helpers} from "../../libraries/helpers/Helpers.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";
import {Errors} from "../../libraries/helpers/Errors.sol";
import {Validation} from "../../libraries/logic/Validation.sol";
import {IGAC} from "../../../interfaces/IGAC.sol";
import {WadMath} from "../../../utils/WadMath.sol";
import {IAutoPoolYieldSource} from "../../../interfaces/IAutoPoolYieldSource.sol";
import {FEYProduct} from "../FEYProduct.sol";

/**
 * @title Fixed and Enhanced Yield AutoPool Product contract
 * @notice Main point of interaction with the FEY product contract
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Claim Excess
 *
 * @author Struct Finance
 */

contract FEYAutoPoolProduct is FEYProduct, TraderJoeLPAdapter {
    using SafeERC20 for IERC20Metadata;
    using WadMath for uint256;

    /// @notice Emitted when the swap path is updated
    /// @param _swapPath Swap path to be updated
    /// @param _path Updated swap path
    event SwapPathUpdated(DataTypes.SwapPathType _swapPath, address[] _path);

    /// @dev The address of the AutoPoolYieldSource contract
    IAutoPoolYieldSource public yieldSource;

    /// @dev Swap paths
    address[] public seniorTokenToJuniorTokenSwapPath;
    address[] public juniorTokenToSeniorTokenSwapPath;
    address[] public seniorTokenToNativeSwapPath;
    address[] public juniorTokenToNativeSwapPath;

    /// @dev Flag to indicate if the product is queued for redemption
    uint256 public isQueuedForWithdrawal = 2; // 1 = true and 2 = false

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
        yieldSource = IAutoPoolYieldSource(_yieldSource);

        slippage = Constants.DEFAULT_SLIPPAGE;
        _srDecimals = _initConfig.configTrancheSr.decimals;
        _jrDecimals = _initConfig.configTrancheJr.decimals;

        trancheTokenSr = _initConfig.configTrancheSr.tokenAddress;
        trancheTokenJr = _initConfig.configTrancheJr.tokenAddress;

        /// @dev Construct swap path array
        address[] memory _seniorTokenToJuniorTokenSwapPath = new address[](2);
        _seniorTokenToJuniorTokenSwapPath[0] = address(_initConfig.configTrancheSr.tokenAddress);
        _seniorTokenToJuniorTokenSwapPath[1] = address(_initConfig.configTrancheJr.tokenAddress);
        seniorTokenToJuniorTokenSwapPath = _seniorTokenToJuniorTokenSwapPath;

        address[] memory _juniorTokenToSeniorTokenSwapPath = new address[](2);
        _juniorTokenToSeniorTokenSwapPath[0] = address(_initConfig.configTrancheJr.tokenAddress);
        _juniorTokenToSeniorTokenSwapPath[1] = address(_initConfig.configTrancheSr.tokenAddress);
        juniorTokenToSeniorTokenSwapPath = _juniorTokenToSeniorTokenSwapPath;

        address[] memory _seniorTokenToNativeSwapPath = new address[](2);
        _seniorTokenToNativeSwapPath[0] = address(_initConfig.configTrancheSr.tokenAddress);
        _seniorTokenToNativeSwapPath[1] = nativeToken;
        seniorTokenToNativeSwapPath = _seniorTokenToNativeSwapPath;

        address[] memory _juniorTokenToNativeSwapPath = new address[](2);
        _juniorTokenToNativeSwapPath[0] = address(_initConfig.configTrancheJr.tokenAddress);
        _juniorTokenToNativeSwapPath[1] = nativeToken;
        juniorTokenToNativeSwapPath = _juniorTokenToNativeSwapPath;

        isInitialized = true;
    }

    /**
     * @notice Method used to invest funds into Autopool to accrue yield
     * @dev This method calls the `supplyToken()` method on {AutoPoolYieldSource} contract
     */
    function invest() external override nonReentrant gacPausable {
        /// Revert if AutoPoolVault deposits are paused
        require((!IAutoPoolVault(yieldSource.autoPoolVault()).isDepositsPaused()), Errors.VE_AUTOPOOLVAULT_PAUSED);

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

        // Move the product state to WITHDRAWN if either of the pools got no deposits
        if (_srTotal == 0 || _jrTotal == 0) {
            _forceUpdateStatusToWithdrawn();
            return;
        }

        (bool _isPriceValidSr, uint256 _jrToSrRate,,) = getTokenRate(DataTypes.Tranche.Senior, 0);
        require(_isPriceValidSr, Errors.PFE_INVALID_SR_PRICE);

        (bool _isPriceValidJr, uint256 _srToJrRate,,) = getTokenRate(DataTypes.Tranche.Junior, 0);
        require(_isPriceValidJr, Errors.PFE_INVALID_JR_PRICE);

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

    function _checkAndUpdateRemoveFundsState() private {
        Validation.validateRemoveFunds(productConfig.endTimeTranche, currentState);
        isQueuedForWithdrawal = 1;
    }

    /**
     * @notice Method used to queue for redemption from the AutoPool
     */
    function removeFundsFromLP() external override nonReentrant gacPausable {
        _checkAndUpdateRemoveFundsState();
        try yieldSource.queueForRedemption() {}
        catch (bytes memory) {
            // If the above call fails, try calling `queueForRedemptionSansRecompound()`
            yieldSource.queueForRedemptionSansRecompound();
        }
        // No event needed here as YieldSource contract already emits `RedemptionQueued` event
    }

    /**
     * @notice Process the redeemed tokens from the AutoPool
     * @param _receivedAmountTokenA  Amount of TokenA received from the AutoPool
     * @param _receivedAmountTokenB Amount of TokenB recieved from the AutoPool
     */

    function processRedemption(uint256 _receivedAmountTokenA, uint256 _receivedAmountTokenB)
        external
        nonReentrant
        gacPausable
    {
        require(msg.sender == address(yieldSource), Errors.ACE_INVALID_ACCESS);
        require(isQueuedForWithdrawal == 1, Errors.VE_INVALID_STATE);

        uint256 _receivedSr;
        uint256 _receivedJr;

        if (address(trancheTokenSr) == address(yieldSource.tokenA())) {
            (_receivedSr, _receivedJr) = (_receivedAmountTokenA, _receivedAmountTokenB);
        } else {
            (_receivedSr, _receivedJr) = (_receivedAmountTokenB, _receivedAmountTokenA);
        }
        uint256 _tokenBalanceBeforeSeniorTranche = trancheTokenSr.balanceOf(address(this));
        uint256 _tokenBalanceBeforeJuniorTranche = trancheTokenJr.balanceOf(address(this));

        trancheTokenSr.safeTransferFrom(address(yieldSource), address(this), _receivedSr);
        trancheTokenJr.safeTransferFrom(address(yieldSource), address(this), _receivedJr);

        _receivedSr = trancheTokenSr.balanceOf(address(this)) - _tokenBalanceBeforeSeniorTranche;
        _receivedJr = trancheTokenJr.balanceOf(address(this)) - _tokenBalanceBeforeJuniorTranche;

        uint256 _srFrFactor = getSrFrFactor(false);

        _receivedSr = Helpers.tokenDecimalsToWei(_srDecimals, _receivedSr);
        _receivedJr = Helpers.tokenDecimalsToWei(_jrDecimals, _receivedJr);

        trancheInfo[DataTypes.Tranche.Senior].tokensReceivedFromLP = _receivedSr;
        trancheInfo[DataTypes.Tranche.Junior].tokensReceivedFromLP = _receivedJr;

        _allocateToTranches(_receivedSr, _receivedJr, _srFrFactor);

        _chargeFee(_receivedSr, _receivedJr);

        /// Capture tokens at maturity
        trancheInfo[DataTypes.Tranche.Senior].tokensAtMaturity = Helpers.tokenDecimalsToWei(
            _srDecimals, Helpers._getTokenBalance(trancheTokenSr, address(this))
        ) - trancheInfo[DataTypes.Tranche.Senior].tokensExcess;
        trancheInfo[DataTypes.Tranche.Junior].tokensAtMaturity = Helpers.tokenDecimalsToWei(
            _jrDecimals, Helpers._getTokenBalance(trancheTokenJr, address(this))
        ) - trancheInfo[DataTypes.Tranche.Junior].tokensExcess;

        isQueuedForWithdrawal = 2;
        currentState = DataTypes.State.WITHDRAWN;

        emit StatusUpdated(DataTypes.State.WITHDRAWN);

        emit RemovedFundsFromLP(
            trancheInfo[DataTypes.Tranche.Senior].tokensAtMaturity,
            trancheInfo[DataTypes.Tranche.Junior].tokensAtMaturity,
            _msgSender()
        );
    }

    /**
     * @notice Used to update the slippage
     * @param _newSlippage The new slippage value to be updated
     */
    function setSlippage(uint256 _newSlippage) external onlyRole(GOVERNANCE) {
        slippage = _newSlippage;
        emit SlippageUpdated(_newSlippage);
    }

    /**
     * @dev Used to update the swap path
     * @param _swapPath The swap path to be updated
     * @param _newPath The new swap path
     */
    function setSwapPath(DataTypes.SwapPathType _swapPath, address[] memory _newPath) external onlyRole(GOVERNANCE) {
        if (_swapPath == DataTypes.SwapPathType.SeniorToNative) {
            seniorTokenToNativeSwapPath = _newPath;
        } else if (_swapPath == DataTypes.SwapPathType.JuniorToNative) {
            juniorTokenToNativeSwapPath = _newPath;
        }
        emit SwapPathUpdated(_swapPath, _newPath);
    }

    /**
     * @notice Returns the rate of the tranche token
     * @param _tranche The tranche id for which the token rate should be fetched.
     * @return bool - Indicates if the price is valid (within max deviation)
     * @return uint256 - AMM rate of the given tranche token against the other tranche token
     * @return uint256 - Price of the given tranche token (Chainlink price)
     * @return uint256 - Price of the other tranche token (Chainlink price)
     */
    function getTokenRate(DataTypes.Tranche _tranche, uint256 _amountOut)
        public
        view
        returns (bool, uint256, uint256, uint256)
    {
        if (_tranche == DataTypes.Tranche.Senior) {
            return
                Helpers.getTrancheTokenRateV2(structPriceOracle, seniorTokenToJuniorTokenSwapPath, lbQuoter, _amountOut);
        } else {
            return
                Helpers.getTrancheTokenRateV2(structPriceOracle, juniorTokenToSeniorTokenSwapPath, lbQuoter, _amountOut);
        }
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
        if (address(trancheTokenSr) == address(yieldSource.tokenA())) {
            (_seniorTokensSupplied, _juniorTokensSupplied) =
                yieldSource.supplyTokens(_tokensInvestableSrInTokenDecimals, _tokensInvestableJrInTokenDecimals);
        } else {
            (_juniorTokensSupplied, _seniorTokensSupplied) =
                yieldSource.supplyTokens(_tokensInvestableJrInTokenDecimals, _tokensInvestableSrInTokenDecimals);
        }
    }

    /**
     * @notice Used to transfer fee when the product is matured
     * @param _receivedSr Senior tokens received from pool
     * @param _receivedJr Junior tokens received from pool
     */
    function _chargeFee(uint256 _receivedSr, uint256 _receivedJr) private {
        (feeTotalSr, feeTotalJr) = Helpers.calculateFees(
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable,
            _receivedSr,
            trancheInfo[DataTypes.Tranche.Junior].tokensInvestable,
            _receivedJr,
            productConfig
        );
        if (feeTotalSr > 0 || feeTotalJr > 0) {
            /// Get nativeToken balance of receiver before sending it fees
            uint256 _receiverNativeBalanceBefore =
                Helpers._getTokenBalance(IERC20Metadata(nativeToken), address(distributionManager));

            if (feeTotalSr > 0) {
                if (address(trancheTokenSr) == address(nativeToken)) {
                    IERC20Metadata(nativeToken).safeTransfer(address(distributionManager), feeTotalSr);
                } else {
                    _swapExact(feeTotalSr, 0, seniorTokenToNativeSwapPath, address(distributionManager));
                }
            }

            if (feeTotalJr > 0) {
                if (address(trancheTokenJr) == address(nativeToken)) {
                    IERC20Metadata(nativeToken).safeTransfer(address(distributionManager), feeTotalJr);
                } else {
                    _swapExact(feeTotalJr, 0, juniorTokenToNativeSwapPath, address(distributionManager));
                }
            }

            /// Get nativeToken balance of receiver after sending it fees
            uint256 _receiverNativeBalanceAfter =
                Helpers._getTokenBalance(IERC20Metadata(nativeToken), address(distributionManager));
            /// Set the difference as the _feeToQueue
            uint256 _feeToQueue = _receiverNativeBalanceAfter - _receiverNativeBalanceBefore;

            distributionManager.queueFees(_feeToQueue);
        }
    }

    /**
     * @notice Reallocate the matured tokens to the tranches
     * @param _receivedSr Amount of senior tokens received from the liquidity pool
     * @param _receivedJr Amount of junior tokens received from the liquidity pool
     * @param _srFrFactor Amount of senior tokens the senior tranche investors expect at maturity
     */
    function _allocateToTranches(uint256 _receivedSr, uint256 _receivedJr, uint256 _srFrFactor) private {
        (bool _isPriceValidSr, uint256 _jrToSrRate,,) = getTokenRate(DataTypes.Tranche.Senior, 0);
        require(_isPriceValidSr, Errors.PFE_INVALID_SR_PRICE);
        /// If the senior tranche tokens received from the liquidity pool is larger than the expected amount
        /// Swap the excess to junior tranche tokens
        if (_receivedSr > _srFrFactor) {
            uint256 _amountToSwap = _receivedSr - _srFrFactor;
            uint256 _expectedJrTokens = _jrToSrRate.wadMul(_amountToSwap);
            _swapExact(
                _amountToSwap,
                _expectedJrTokens - ((_expectedJrTokens * slippage) / Constants.DECIMAL_FACTOR),
                seniorTokenToJuniorTokenSwapPath,
                address(this)
            );
            /// If the senior tranche tokens received from the liquidity pool is smaller than the expected amount
        } else if (_receivedSr < _srFrFactor) {
            uint256 _seniorDelta = _srFrFactor - _receivedSr;
            /// convert delta owed to senior tranche from wei to senior token decimals
            uint256 _amountOut = Helpers.weiToTokenDecimals(_srDecimals, _seniorDelta);
            /// get quote for the amount of junior tokens to swap from senior amount out
            ILBQuoter.Quote memory _quote =
                lbQuoter.findBestPathFromAmountOut(juniorTokenToSeniorTokenSwapPath, uint128(_amountOut));
            uint256 _amountInMax = _quote.amounts[0];
            // add slippage factor to max amount of tokens to swap
            _amountInMax += _amountInMax.mulDiv(slippage, Constants.DECIMAL_FACTOR);
            /// convert max amount of junior tokens to swap from junior token decimals to wei for comparison
            uint256 _amountInMaxWei = Helpers.tokenDecimalsToWei(trancheTokenJr.decimals(), _amountInMax);

            (bool _isPriceValidJr, uint256 _srToJrRate,,) = getTokenRate(DataTypes.Tranche.Junior, _seniorDelta);
            require(_isPriceValidJr, Errors.PFE_INVALID_JR_PRICE);
            uint256 _jrToSwap = (_seniorDelta).wadDiv(_srToJrRate);
            /// And if it is bigger than both junior and senior tranche tokens received from the liquidity pool
            /// Or if the max amount of junior tokens to swap is greater than the amount of junior tokens received
            if (_jrToSwap >= _receivedJr || _amountInMaxWei >= _receivedJr) {
                // swap all the received jr tokens to sr
                uint256 _expectedSrTokens = _srToJrRate.wadMul(_receivedJr);
                _swapExact(
                    _receivedJr,
                    _expectedSrTokens - ((_expectedSrTokens * slippage) / Constants.DECIMAL_FACTOR),
                    juniorTokenToSeniorTokenSwapPath,
                    address(this)
                );
                /// Swap the necessary amount to fill the expected to senior tranche tokens
            } else {
                _swapToExact(_quote, _amountInMax, _amountOut, address(this));
            }
        }
    }

    /**
     * @notice Calculate the amount of senior tokens owed to the senior tranche for the given tranche duration
     * @param _isProrated Whether the the term duration is prorated
     * @return _srFrFactor The amount of senior tokens owed to the senior tranche for the given tranche duration
     */
    function getSrFrFactor(bool _isProrated) public view returns (uint256 _srFrFactor) {
        uint256 _trancheDuration = _isProrated
            ? block.timestamp - productConfig.startTimeTranche
            : productConfig.endTimeTranche - productConfig.startTimeTranche;

        /// Calculate the amount of senior tokens the senior tranche investors expect at maturity
        /// The simplified formula is: (tokensInvestable * (1 + fixedRate * trancheDuration / 1 year))
        _srFrFactor = (
            trancheInfo[DataTypes.Tranche.Senior].tokensInvestable * Constants.YEAR_IN_SECONDS
                + trancheInfo[DataTypes.Tranche.Senior].tokensInvestable * productConfig.fixedRate * _trancheDuration
                    / Constants.DECIMAL_FACTOR
        ) / Constants.YEAR_IN_SECONDS;
    }
}
