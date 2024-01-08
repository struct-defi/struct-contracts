/**
 *                 ██████████████████████████████████████████████████
 *                 ███████████████████████▀░░▀███████████████████████
 *                 ███████████████████▀▀░░░░░░░░▀▀███████████████████
 *                 █████████████████░░░░▄▄████▄▄░░░▐▀████████████████
 *                 ████████████████░░░▓██▀▀▀▀████▌░ ░████████████████
 *                 ████████████████░░░███▄▄░░░▐▀███▄░████████████████
 *                 ████████████████▄░░░░▀▀███▄░░░ ▀▀█████████████████
 *                 ███████████████████▄▄░░░▐▀███▄ ░ ▐████████████████
 *                 ████████████████░░░████▄░░░░███░ ░████████████████
 *                 ████████████████░░░░▀████████▀▀░ ░████████████████
 *                 ██████████████████▄░░░░▀██▀░░░░▄▄█████████████████
 *                 █████████████████████▄▒░░░░░▄▄████████████████████
 *                 ████████████████████████▄▄████████████████████████
 *                 ██████████████████████████████████████████████████
 *
 *
 *                 ░██████╗████████╗██████╗░██╗░░░██╗░█████╗░████████╗
 *                 ██╔════╝╚══██╔══╝██╔══██╗██║░░░██║██╔══██╗╚══██╔══╝
 *                 ╚█████╗░░░░██║░░░██████╔╝██║░░░██║██║░░╚═╝░░░██║░░░
 *                 ░╚═══██╗░░░██║░░░██╔══██╗██║░░░██║██║░░██╗░░░██║░░░
 *                 ██████╔╝░░░██║░░░██║░░██║╚██████╔╝╚█████╔╝░░░██║░░░
 *                 ╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝░╚═════╝░░╚════╝░░░░╚═╝░░░
 *
 *     ███████╗███████╗██╗░░░██╗  ███████╗░█████╗░░█████╗░████████╗░█████╗░██████╗░██╗░░░██╗
 *     ██╔════╝██╔════╝╚██╗░██╔╝  ██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗╚██╗░██╔╝
 *     █████╗░░█████╗░░░╚████╔╝░  █████╗░░███████║██║░░╚═╝░░░██║░░░██║░░██║██████╔╝░╚████╔╝░
 *     ██╔══╝░░██╔══╝░░░░╚██╔╝░░  ██╔══╝░░██╔══██║██║░░██╗░░░██║░░░██║░░██║██╔══██╗░░╚██╔╝░░
 *     ██║░░░░░███████╗░░░██║░░░  ██║░░░░░██║░░██║╚█████╔╝░░░██║░░░╚█████╔╝██║░░██║░░░██║░░░
 *     ╚═╝░░░░░╚══════╝░░░╚═╝░░░  ╚═╝░░░░░╚═╝░░╚═╝░╚════╝░░░░╚═╝░░░░╚════╝░╚═╝░░╚═╝░░░╚═╝░░░
 */

// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/// External Imports
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Internal Imports
import {IAutoPoolYieldSource} from "../../../interfaces/IAutoPoolYieldSource.sol";
import {IFEYProduct} from "../../../interfaces/IFEYProduct.sol";
import {IFEYFactory} from "../../../interfaces/IFEYFactory.sol";
import {ISPToken} from "../../../interfaces/ISPToken.sol";
import {IStructPriceOracle} from "../../../interfaces/IStructPriceOracle.sol";
import {IDistributionManager} from "../../../interfaces/IDistributionManager.sol";

import {IGAC} from "../../../interfaces/IGAC.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";
import {Errors} from "../../libraries/helpers/Errors.sol";
import {WadMath} from "../../../utils/WadMath.sol";
import {IAutoPoolVault} from "../../../external/traderjoe/IAutoPoolVault.sol";

import {FEYFactoryConfigurator} from "../FEYFactoryConfigurator.sol";

/**
 * @title Fixed and Enhanced Yield Product Factory Contract
 * @notice Factory contract that is used to create Fixed and Enhanced Yield AutoPool Products
 * @author Struct Finance
 */

contract FEYAutoPoolProductFactory is FEYFactoryConfigurator, IFEYFactory {
    using WadMath for uint256;
    using SafeERC20 for IERC20Metadata;

    /// @dev Keeps track of the latest SP token ID
    uint256 public latestSpTokenId;

    /// @dev Address of the StructSP Token
    ISPToken public spTokenAddress;

    /// @dev Address of the Native token
    IERC20Metadata public immutable wAVAX;

    /// @dev Active products
    mapping(address => uint256) public isProductActive;

    /// @dev Active pairs
    mapping(address => mapping(address => uint256)) public isPoolActive;

    /// @dev Vaults mapping for reverse loopup
    mapping(address => mapping(address => address)) public autoPoolVaults;

    /// @dev TokenID => Product
    mapping(uint256 => address) public productTokenId;

    /// @dev List of addresses of all the FEYProducts created
    address[] public allProducts;

    /// @dev AutoPoool vault => YieldSource
    mapping(address => IAutoPoolYieldSource) public yieldSources;

    /**
     * @notice Initializes the Factory based on the given parameter
     * @param _spTokenAddress Address of the Struct SP Token
     * @param _feyProductImpl Address for FEYProduct implementation
     * @param _globalAccessControl Address of the StructGAC contract
     * @param _priceOracle The address of the struct price oracle
     * @param _wAVAX wAVAX address
     * @param _distributionManager Address of the distribution manager contract
     */
    constructor(
        ISPToken _spTokenAddress,
        address _feyProductImpl,
        IGAC _globalAccessControl,
        IStructPriceOracle _priceOracle,
        IERC20Metadata _wAVAX,
        IDistributionManager _distributionManager
    ) {
        __GACManaged_init(_globalAccessControl);
        spTokenAddress = _spTokenAddress;
        feyProductImplementation = _feyProductImpl;
        structPriceOracle = _priceOracle;
        distributionManager = _distributionManager;
        wAVAX = _wAVAX;

        emit FactoryGACInitialized(address(_globalAccessControl));
    }

    /**
     * @notice Returns the total number of products created
     */
    function totalProducts() external view returns (uint256) {
        return allProducts.length;
    }

    /**
     * @notice Creates new FEY Products based on the given specifications
     * @dev If the caller is not `WHITELISTED`, an initial deposit should be made.
     * @dev The contract should not be in the `PAUSED` state
     * @param _configTrancheSr Configuration of the senior tranche
     * @param _configTrancheJr Configuration of the junior tranche
     * @param _productConfigUserInput User-set configuration of the Product
     * @param _tranche The tranche into which the creater makes the initial deposit
     * @param _initialDepositAmount The initial deposit amount
     */
    function createProduct(
        DataTypes.TrancheConfig memory _configTrancheSr,
        DataTypes.TrancheConfig memory _configTrancheJr,
        DataTypes.ProductConfigUserInput memory _productConfigUserInput,
        DataTypes.Tranche _tranche,
        uint256 _initialDepositAmount
    ) external payable gacPausable {
        (uint256 _initialDepositValueUSD, address _trancheToken) = _getInitialDepositValueUSD(
            _tranche,
            _initialDepositAmount,
            address(_configTrancheSr.tokenAddress),
            address(_configTrancheJr.tokenAddress)
        );
        /// @dev Validate if the initial deposit value is >= the minimumInitialDeposit
        /// @dev If not, then the product creator should be whitelisted.
        if (_initialDepositValueUSD < minimumInitialDepositUSD) {
            require(gac.hasRole(WHITELISTED, _msgSender()), Errors.ACE_INVALID_ACCESS);
        }

        _validatePool(address(_configTrancheSr.tokenAddress), address(_configTrancheJr.tokenAddress));

        require(isTokenActive[address(_configTrancheSr.tokenAddress)] == TRUE, Errors.VE_TOKEN_INACTIVE);
        require(isTokenActive[address(_configTrancheJr.tokenAddress)] == TRUE, Errors.VE_TOKEN_INACTIVE);
        address _newProduct;
        DataTypes.ProductConfig memory _productConfig;

        _productConfig.fixedRate = _productConfigUserInput.fixedRate;
        _productConfig.startTimeTranche = _productConfigUserInput.startTimeTranche;
        _productConfig.endTimeTranche = _productConfigUserInput.endTimeTranche;
        _productConfig.leverageThresholdMin = _productConfigUserInput.leverageThresholdMin;
        _productConfig.leverageThresholdMax = _productConfigUserInput.leverageThresholdMax;

        {
            _productConfig.startTimeDeposit = block.timestamp;

            _validateProductConfig(_productConfig);

            _newProduct = _deployProduct(_configTrancheSr, _configTrancheJr, _productConfig);
        }

        {
            emit ProductCreated(
                _newProduct,
                _productConfig.fixedRate,
                _productConfig.startTimeDeposit,
                _productConfig.startTimeTranche,
                _productConfig.endTimeTranche
            );

            emit TrancheCreated(
                _newProduct, DataTypes.Tranche.Junior, address(_configTrancheJr.tokenAddress), _configTrancheJr.capacity
            );

            emit TrancheCreated(
                _newProduct, DataTypes.Tranche.Senior, address(_configTrancheSr.tokenAddress), _configTrancheSr.capacity
            );
        }

        if (_initialDepositValueUSD > 0) {
            _makeInitialDeposit(
                _tranche, _initialDepositAmount, IERC20Metadata(_trancheToken), IFEYProduct(_newProduct)
            );
        }
    }

    /**
     * @notice Used to update the status of pair
     * @param _autoPoolVault The addresss of the autopool vault contract
     * @param _status The status of the pair
     */
    function setPoolStatus(address _autoPoolVault, uint256 _status) external onlyRole(GOVERNANCE) {
        require(_status == TRUE || _status == FALSE, Errors.VE_INVALID_STATUS);

        address _token0 = IAutoPoolVault(_autoPoolVault).getTokenX();
        address _token1 = IAutoPoolVault(_autoPoolVault).getTokenY();

        isPoolActive[_token0][_token1] = _status;
        isPoolActive[_token1][_token0] = _status;

        autoPoolVaults[_token0][_token1] = _autoPoolVault;
        autoPoolVaults[_token1][_token0] = _autoPoolVault;
        emit PoolStatusUpdated(_autoPoolVault, _status, _token0, _token1);
    }

    /**
     * @notice Sets yield-source contract address for the AutoPool vault
     * @param _autoPoolVault Address of the AutoPool Vault contract
     * @param _yieldSource Address of the yield source contract
     */
    function setYieldSource(address _autoPoolVault, address _yieldSource) external onlyRole(GOVERNANCE) {
        require(address(_yieldSource) != address(0), Errors.AE_ZERO_ADDRESS);

        address yieldSourceTokenA = address(IAutoPoolYieldSource(_yieldSource).tokenA());
        address yieldSourceTokenB = address(IAutoPoolYieldSource(_yieldSource).tokenB());

        address autoPoolVaultTokenA = IAutoPoolVault(_autoPoolVault).getTokenX();
        address autoPoolVaultTokenB = IAutoPoolVault(_autoPoolVault).getTokenY();

        require(
            (yieldSourceTokenA == autoPoolVaultTokenA && yieldSourceTokenB == autoPoolVaultTokenB)
                || (yieldSourceTokenA == autoPoolVaultTokenB && yieldSourceTokenB == autoPoolVaultTokenA),
            Errors.AE_INVALID_YIELDSOURCE
        );

        yieldSources[_autoPoolVault] = IAutoPoolYieldSource(_yieldSource);
        emit YieldSourceAdded(_autoPoolVault, _yieldSource, yieldSourceTokenA, yieldSourceTokenB);
    }

    /**
     * @notice Checks if spToken can still be minted for the given product.
     * @dev SPTokens should be minted only for the products with `OPEN` state
     * @param _spTokenId The SPTokenId associated with the product (senior/junior tranche)
     * @return A flag indicating if SPTokens can be minted
     */
    function isMintActive(uint256 _spTokenId) external view returns (bool) {
        return (IFEYProduct(productTokenId[_spTokenId]).getCurrentState() == DataTypes.State.OPEN);
    }

    /**
     * @notice Checks if the SPToken with the given ID can be transferred.
     * @param _spTokenId The SPToken Id
     * @param _user Address of the SPToken holder
     * @return A flag indicating if transfers are allowed or not
     */
    function isTransferEnabled(uint256 _spTokenId, address _user) external view returns (bool) {
        IFEYProduct _feyProduct = IFEYProduct(productTokenId[_spTokenId]);

        /// Restrict transfer when the product state is `OPEN`
        if (_feyProduct.getCurrentState() == DataTypes.State.OPEN) return false;

        DataTypes.Tranche _tranche = _spTokenId % 2 == 0 ? DataTypes.Tranche.Senior : DataTypes.Tranche.Junior;

        (, uint256 _excess) = _feyProduct.getUserInvestmentAndExcess(_tranche, _user);

        DataTypes.Investor memory _investor = _feyProduct.getInvestorDetails(_tranche, _user);

        if (_excess == 0 || _investor.claimed) return true;
        return false;
    }

    /**
     * @notice Deploys the FEY Product based on the given config
     * @param _configTrancheSr - The configuration for the Senior Tranche
     * @param _configTrancheJr - The configuration for the Junior Tranche
     * @param _productConfig - The configuration for the new product
     * @return The address of the new product
     */
    function _deployProduct(
        DataTypes.TrancheConfig memory _configTrancheSr,
        DataTypes.TrancheConfig memory _configTrancheJr,
        DataTypes.ProductConfig memory _productConfig
    ) private returns (address) {
        _configTrancheJr.spTokenId = latestSpTokenId + 1;
        _configTrancheSr.spTokenId = latestSpTokenId + 2;

        _configTrancheSr.decimals = _configTrancheSr.tokenAddress.decimals();
        _configTrancheJr.decimals = _configTrancheJr.tokenAddress.decimals();

        _productConfig.managementFee = managementFee;
        _productConfig.performanceFee = performanceFee;

        address _srTrancheTokenAddress = address(_configTrancheSr.tokenAddress);
        address _jrTrancheTokenAddress = address(_configTrancheJr.tokenAddress);

        address _yieldSource = address(yieldSources[autoPoolVaults[_srTrancheTokenAddress][_jrTrancheTokenAddress]]);

        require(_yieldSource != address(0), Errors.AE_YIELDSOURCE_NOT_SET);

        (_configTrancheSr.capacity, _configTrancheJr.capacity) =
            _getTrancheCapacityValues(_srTrancheTokenAddress, _jrTrancheTokenAddress);

        address _newProduct = Clones.cloneDeterministic(
            feyProductImplementation,
            keccak256( // salt
            abi.encodePacked(_srTrancheTokenAddress, _jrTrancheTokenAddress, _configTrancheJr.spTokenId))
        );

        DataTypes.InitConfigParam memory _initConfig =
            DataTypes.InitConfigParam(_configTrancheSr, _configTrancheJr, _productConfig);
        IFEYProduct(_newProduct).initialize(
            _initConfig,
            structPriceOracle,
            spTokenAddress,
            gac,
            distributionManager,
            _yieldSource,
            payable(address(wAVAX))
        );

        gac.grantRole(PRODUCT, _newProduct);

        latestSpTokenId += 2;

        allProducts.push(_newProduct);

        productTokenId[_configTrancheSr.spTokenId] = _newProduct;
        productTokenId[_configTrancheJr.spTokenId] = _newProduct;

        return _newProduct;
    }

    /**
     * @notice Used to increase allowance and deposit on behalf of the product creator
     * @param _tranche Tranche id to make the initial deposit
     * @param _amount Amount of tokens to be deposited
     * @param _trancheToken Tranche token address
     * @param _productAddress FEYProduct address that's recently deployed
     */
    function _makeInitialDeposit(
        DataTypes.Tranche _tranche,
        uint256 _amount,
        IERC20Metadata _trancheToken,
        IFEYProduct _productAddress
    ) private {
        if (msg.value != 0) {
            require(address(_trancheToken) == address(wAVAX), Errors.VE_INVALID_NATIVE_TOKEN_DEPOSIT);
            _productAddress.depositFor{value: msg.value}(_tranche, _amount, _msgSender());
        } else {
            uint256 _balanceBefore = _trancheToken.balanceOf(address(this));
            _trancheToken.safeTransferFrom(_msgSender(), address(this), _amount);
            uint256 _balanceAfter = _trancheToken.balanceOf(address(this));
            require(_balanceAfter - _balanceBefore >= _amount, Errors.VE_INVALID_TRANSFER_AMOUNT);
            _trancheToken.safeIncreaseAllowance(address(_productAddress), _amount);
            _productAddress.depositFor(_tranche, _amount, _msgSender());
        }
    }

    /**
     * @notice Validates the Product configuration
     * @param _productConfig Product configuration
     */
    function _validateProductConfig(DataTypes.ProductConfig memory _productConfig) private view {
        require(_productConfig.fixedRate < maxFixedRate && _productConfig.fixedRate != 0, Errors.VE_INVALID_RATE);

        require(_productConfig.startTimeTranche > _productConfig.startTimeDeposit, Errors.VE_INVALID_TRANCHE_START_TIME);
        require(_productConfig.endTimeTranche > _productConfig.startTimeTranche, Errors.VE_INVALID_TRANCHE_END_TIME);

        uint256 _trancheDuration = _productConfig.endTimeTranche - _productConfig.startTimeTranche;

        require(
            _trancheDuration >= trancheDurationMin && _trancheDuration < trancheDurationMax,
            Errors.VE_INVALID_TRANCHE_DURATION
        );

        require(_productConfig.leverageThresholdMin <= leverageThresholdMinCap, Errors.VE_INVALID_LEV_MIN);
        require(_productConfig.leverageThresholdMax >= leverageThresholdMaxCap, Errors.VE_INVALID_LEV_MAX);
        require(
            _productConfig.leverageThresholdMax <= _productConfig.leverageThresholdMin, Errors.VE_LEV_MAX_GT_LEV_MIN
        );
    }

    /**
     * @notice Validates if pool exists for the given set of tokens and the autopool vault is not paused.
     * @param _token0 Address for token0
     * @param _token1 Address for token1
     */
    function _validatePool(address _token0, address _token1) private view {
        if (isPoolActive[_token0][_token1] != TRUE || isPoolActive[_token1][_token0] != TRUE) {
            revert(Errors.VE_INVALID_POOL);
        }

        IAutoPoolVault _autoPoolVault = IAutoPoolVault(autoPoolVaults[_token0][_token1]);
        require(!_autoPoolVault.isDepositsPaused(), Errors.VE_AUTOPOOLVAULT_PAUSED);
    }

    /**
     * @notice Returns the tranche capacity values in USD.
     * @param _trancheTokenSenior Senior tranche token address
     * @param _trancheTokenJunior Junior tranche token address
     * @return _trancheCapacityValueSenior Value of Senior tranche capacity in USD
     * @return _trancheCapacityValueJunior Value of Junior tranche capacity in USD
     */
    function _getTrancheCapacityValues(address _trancheTokenSenior, address _trancheTokenJunior)
        private
        view
        returns (uint256 _trancheCapacityValueSenior, uint256 _trancheCapacityValueJunior)
    {
        uint256 _trancheCapUSD = trancheCapacityUSD;
        _trancheCapacityValueSenior = (_trancheCapUSD).wadDiv(structPriceOracle.getAssetPrice(_trancheTokenSenior));

        _trancheCapacityValueJunior = (_trancheCapUSD).wadDiv(structPriceOracle.getAssetPrice(_trancheTokenJunior));
    }

    /**
     * @notice Returns the initial deposit amount value in USD
     * @param _tranche Tranche for initial deposit
     * @param _amount The initial deposit amount
     * @param _trancheTokenSenior Senior tranche token address
     * @param _trancheTokenJunior Junior tranche token address
     * @return _valueUSD Value of initial deposit amount in USD
     * @return _trancheToken Address of the tranche token
     */
    function _getInitialDepositValueUSD(
        DataTypes.Tranche _tranche,
        uint256 _amount,
        address _trancheTokenSenior,
        address _trancheTokenJunior
    ) private view returns (uint256 _valueUSD, address _trancheToken) {
        if (_tranche == DataTypes.Tranche.Senior) {
            _trancheToken = _trancheTokenSenior;
        } else if (_tranche == DataTypes.Tranche.Junior) {
            _trancheToken = _trancheTokenJunior;
        }
        uint256 _amountScaled = _amount.mulDiv(Constants.WAD, 10 ** IERC20Metadata(_trancheToken).decimals());
        _valueUSD = structPriceOracle.getAssetPrice(_trancheToken).wadMul(_amountScaled);
    }
}
