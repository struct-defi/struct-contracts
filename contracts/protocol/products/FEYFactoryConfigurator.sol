// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/// Internal Imports
import {IStructPriceOracle} from "../../interfaces/IStructPriceOracle.sol";
import {IDistributionManager} from "../../interfaces/IDistributionManager.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {GACManaged} from "../common/GACManaged.sol";

/**
 * @title FEYProductFactory Configurator contract
 * @notice Configurator contract that is used to update the configuration of the {FEYFactory} contracts.
 * @dev This contract will be inherited by {FEYFactory} contracts.
 * @author Struct Finance
 */

abstract contract FEYFactoryConfigurator is GACManaged {
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
    event TokenStatusUpdated(address indexed token, uint256 status);

    /// @dev Address of the Struct price oracle
    IStructPriceOracle public structPriceOracle;

    /// @dev Address of the Distribution manager
    IDistributionManager public distributionManager;

    /// @dev Address of the FEYProduct implementation
    address public feyProductImplementation;

    /// @dev management fee
    uint256 public managementFee = 0; // 0%

    /// @dev performance fee
    uint256 public performanceFee = 0; // 0%

    /// @dev Default tranche capacity for the tranches in USD
    uint256 public trancheCapacityUSD = 1_000_000 * 10 ** 18; // 1M

    /**
     * @notice leverageThresholdMinCap > leverageThresholdMaxCap because the value
     * indictates the max/min amount of jr tranche tokens that is
     * allowable (in relation to amount of sr tranche tokens). The smaller
     * the allowable value, the larger the leverage. Hence the smaller the
     * leveragethreshold value, the larger the leverage.
     * @dev Limit for the leverage threshold min
     */
    uint256 public leverageThresholdMinCap = 1500000; // 150%

    /// @dev Limit for the leverage threshold max
    uint256 public leverageThresholdMaxCap = 500000; // 50%

    /// @dev Min/Max Tranche duration
    uint256 public trancheDurationMin = 7 * 24 * 60 * 60; // 7 days
    uint256 public trancheDurationMax = 200 * 24 * 60 * 60; // ~6.5 months

    /// @dev The minimum initial deposit value in USD that the product creator should make.
    /// @dev This is applicable only for non-whitelisted creators
    uint256 public minimumInitialDepositUSD = 100 * 10 ** 18;

    /// @dev Declare TRUE/FALSE. Saves a bit of gas
    uint256 internal constant TRUE = 1;
    uint256 internal constant FALSE = 2;

    uint256 public maxFixedRate = 750000; // 75%

    /// @dev Active tokens
    mapping(address => uint256) public isTokenActive;
    /**
     * @notice Sets the StructPriceOracle.
     * @param _structPriceOracle The StructPriceOracle Interface
     */

    function setStructPriceOracle(IStructPriceOracle _structPriceOracle) external onlyRole(GOVERNANCE) {
        require(address(_structPriceOracle) != address(0), Errors.VE_INVALID_ZERO_ADDRESS);
        structPriceOracle = _structPriceOracle;
        emit StructPriceOracleUpdated(address(_structPriceOracle));
    }

    /**
     * @notice Sets the minimum tranche duration.
     * @param _trancheDurationMin Minimum tranche duration in seconds
     */
    function setMinimumTrancheDuration(uint256 _trancheDurationMin) external onlyRole(GOVERNANCE) {
        require(_trancheDurationMin != 0, Errors.VE_INVALID_ZERO_VALUE);
        trancheDurationMin = _trancheDurationMin;
        emit TrancheDurationMinUpdated(_trancheDurationMin);
    }

    /**
     * @notice Sets the maximum tranche duration.
     * @param _trancheDurationMax Maximum tranche duration in seconds
     */
    function setMaximumTrancheDuration(uint256 _trancheDurationMax) external onlyRole(GOVERNANCE) {
        require(_trancheDurationMax != 0, Errors.VE_INVALID_ZERO_VALUE);
        require(_trancheDurationMax >= trancheDurationMin, Errors.VE_INVALID_TRANCHE_DURATION_MAX);
        trancheDurationMax = _trancheDurationMax;
        emit TrancheDurationMaxUpdated(_trancheDurationMax);
    }

    /**
     * @notice Sets the management fee.
     * @param _managementFee The management fee in basis points (bps)
     */
    function setManagementFee(uint256 _managementFee) external onlyRole(GOVERNANCE) {
        managementFee = _managementFee;
        emit ManagementFeeUpdated(_managementFee);
    }

    /**
     * @notice Sets the performance fee
     * @param _performanceFee The performance fee in bps
     */

    function setPerformanceFee(uint256 _performanceFee) external onlyRole(GOVERNANCE) {
        performanceFee = _performanceFee;
        emit PerformanceFeeUpdated(_performanceFee);
    }

    /**
     * @notice Sets the minimum leverage threshold.
     * @param _levThresholdMin Minimum laverage treshold in bps
     */
    function setLeverageThresholdMinCap(uint256 _levThresholdMin) external onlyRole(GOVERNANCE) {
        require(_levThresholdMin >= leverageThresholdMaxCap, Errors.VE_INVALID_LEV_THRESH_MIN);
        leverageThresholdMinCap = _levThresholdMin;
        emit LeverageThresholdMinUpdated(_levThresholdMin);
    }

    /**
     * @notice Sets the maximum leverage threshold.
     * @param _levThresholdMax Maximum leverage threshold bps
     */
    function setLeverageThresholdMaxCap(uint256 _levThresholdMax) external onlyRole(GOVERNANCE) {
        require(_levThresholdMax <= leverageThresholdMinCap, Errors.VE_INVALID_LEV_THRESH_MAX);
        leverageThresholdMaxCap = _levThresholdMax;
        emit LeverageThresholdMaxUpdated(_levThresholdMax);
    }

    /**
     * @notice Used to update a token status (active/inactive)
     * @param _token The token address
     * @param _status The status of the token
     */
    function setTokenStatus(address _token, uint256 _status) external virtual onlyRole(GOVERNANCE) {
        require(_status == TRUE || _status == FALSE, Errors.VE_INVALID_STATUS);
        require(_token != address(0), Errors.VE_INVALID_TOKEN);
        isTokenActive[_token] = _status;
        emit TokenStatusUpdated(_token, _status);
    }

    /**
     * @notice Sets the new default tranche capacity.
     * @param _trancheCapUSD New capacity in USD
     */
    function setTrancheCapacity(uint256 _trancheCapUSD) external onlyRole(GOVERNANCE) {
        require(_trancheCapUSD > minimumInitialDepositUSD, Errors.VE_INVALID_TRANCHE_CAP);
        trancheCapacityUSD = _trancheCapUSD;
        emit TrancheCapacityUpdated(_trancheCapUSD);
    }

    /**
     * @notice Sets the new max fixed rate allowed.
     * @param _newMaxFixedRate New max fixed rate bps
     */
    function setMaxFixedRate(uint256 _newMaxFixedRate) external onlyRole(GOVERNANCE) {
        require(_newMaxFixedRate > 0, Errors.VE_INVALID_RATE);
        maxFixedRate = _newMaxFixedRate;
        emit MaxFixedRateUpdated(_newMaxFixedRate);
    }

    /**
     * @notice Sets the new FEYProduct implementation address
     * @dev All the upcoming products will use the updated implementation
     * @param _feyProductImpl Address of the new FEYProduct contract
     */
    function setFEYProductImplementation(address _feyProductImpl) external onlyRole(GOVERNANCE) {
        require(address(_feyProductImpl) != address(0), Errors.VE_INVALID_ZERO_ADDRESS);
        address _oldImpl = feyProductImplementation;
        feyProductImplementation = _feyProductImpl;

        emit FEYProductImplementationUpdated(_oldImpl, _feyProductImpl);
    }
    /**
     * @notice Sets the new minimum initial deposit value.
     * @param _newValue New initial minimum deposit value in USD
     */

    function setMinimumDepositValueUSD(uint256 _newValue) external onlyRole(GOVERNANCE) {
        require(_newValue > 0 && _newValue < trancheCapacityUSD, Errors.VE_MIN_DEPOSIT_VALUE);
        minimumInitialDepositUSD = _newValue;
        emit MinimumInitialDepositValueUpdated(_newValue);
    }
}
