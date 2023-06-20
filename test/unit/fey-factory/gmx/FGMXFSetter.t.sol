// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@mocks/MockERC20.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IFEYFactory.sol";
import "@interfaces/IGMXYieldSource.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@core/common/StructPriceOracle.sol";

import "../../../common/fey-factory/gmx/FEYFactoryBaseTestSetup.sol";

contract FGMXFSetterTest is FEYFactoryBaseTestSetup {
    uint256 internal _managementFee = 1e6;

    event TokenStatusUpdated(address indexed token, uint256 status);

    event PerformanceFeeUpdated(uint256 performanceFee);
    event ManagementFeeUpdated(uint256 _managementFee);

    event LeverageThresholdMinUpdated(uint256 levThresholdMin);
    event LeverageThresholdMaxUpdated(uint256 levThresholdMax);

    event TrancheDurationMinUpdated(uint256 minTrancheDuration);
    event TrancheDurationMaxUpdated(uint256 maxTrancheDuration);

    event StructPriceOracleUpdated(address indexed structPriceOracle);

    event TrancheCapacityUpdated(uint256 defaultTrancheCapUSD);

    event MinimumInitialDepositValueUpdated(uint256 newValue);

    event FEYProductImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);

    event PoolStatusUpdated(address indexed lpAddress, uint256 status, address indexed tokenA, address indexed tokenB);

    event FactoryGACInitialized(address indexed gac);

    function onSetup() public virtual override {
        factoryTestsFixture();
    }

    function testSetter_setTokenStatus_Success_EmitTokenStatusUpdated() public {
        console.log("ID: Fa_STS_1");
        console.log("ID: GMX_Fa_STS_2");
        console.log("should succeed and emit event TokenStatusUpdated if called by governance role");
        console.log("token is included in the GMX pool whitelist");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(true));
        vm.expectEmit(true, true, true, true);
        emit TokenStatusUpdated(address(usdc), 1);
        admin.setTokenStatus(address(usdc), 1);
    }

    function testSetter_setTokenStatus_RevertInvalidAccess() public {
        console.log("ID: Fa_STS_2");
        console.log("should revert with error ACE_INVALID_ACCESS if called by non-governance role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user3.setTokenStatus(address(usdc), 1);
    }

    function testSetter_setTokenStatus_RevertInvalidTokenZeroAddress() public {
        console.log("ID: Fa_STS_3");
        console.log("should revert with error VE_INVALID_TOKEN if new token address is zero address");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(false));
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TOKEN));
        admin.setTokenStatus(address(0), 1);
    }

    function testSetter_setTokenStatus_RevertInvalidTokenNotWhitelisted() public {
        console.log("ID: GMX_Fa_STS_1");
        console.log("should revert with error VE_INVALID_TOKEN if new token address is not whitelisted by GMX Vault");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(false));
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TOKEN));
        admin.setTokenStatus(address(usdc), 1);
    }

    function testSetter_setPerformanceFee_EmitPerformanceFeeUpdated() public {
        console.log("ID: Fa_SPF_1");
        console.log("should emit the PerformanceFeeUpdated event when called by governance role account");
        vm.expectEmit(true, true, true, true);
        emit PerformanceFeeUpdated(_managementFee);
        admin.setPerformanceFee(_managementFee);
    }

    function testSetter_setPerformanceFee_ZeroValue() public {
        console.log("ID: Fa_SPF_2");
        console.log("performanceFee should be equal to the zero value set");
        uint256 zeroValue;
        admin.setPerformanceFee(zeroValue);
        uint256 newFee = sut.performanceFee();
        assertEq(zeroValue, newFee);
    }

    function testSetter_setPerformanceFee_RevertInvalidAccess() public {
        console.log("ID: Fa_SPF_3");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setPerformanceFee(_managementFee);
    }

    function testSetter_setManagementFee_EmitManagementFeeUpdated() public {
        console.log("ID: Fa_SMF_1");
        console.log("should emit the PerformanceFeeUpdated event when called by governance role account");
        vm.expectEmit(true, true, true, true);
        emit ManagementFeeUpdated(_managementFee);
        admin.setManagementFee(_managementFee);
    }

    function testSetter_setManagementFee_ZeroValue() public {
        console.log("ID: Fa_SMF_2");
        console.log("managementFee should be equal to the zero value set");
        uint256 zeroValue;
        admin.setManagementFee(zeroValue);
        uint256 newFee = sut.managementFee();
        assertEq(zeroValue, newFee);
    }

    function testSetter_setManagementFee_RevertInvalidAccess() public {
        console.log("ID: Fa_SMF_3");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setManagementFee(_managementFee);
    }

    function testSetter_setLeverageThresholdMinCap_Success() public {
        console.log("ID: Fa_SLTMi_1");
        console.log("should emit LeverageThresholdMinUpdated when called by governance");
        vm.expectEmit(true, true, true, true);
        emit LeverageThresholdMinUpdated(_managementFee);
        admin.setLeverageThresholdMinCap(_managementFee);
        console.log("should set the leverage threshold min limit when called by governance");
        uint256 _newVal = sut.leverageThresholdMinCap();
        assertEq(_newVal, _managementFee);
    }

    function testSetter_setLeverageThresholdMinCap_RevertInvalidAccess() public {
        console.log("ID: Fa_SLTMi_2");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setLeverageThresholdMinCap(_managementFee);
    }

    function testSetter_setLeverageThresholdMaxCap_Success() public {
        console.log("ID: Fa_SLTMa_1");
        console.log("should emit LeverageThresholdMaxUpdated when called by governance");
        vm.expectEmit(true, true, true, true);
        emit LeverageThresholdMaxUpdated(_managementFee);
        admin.setLeverageThresholdMaxCap(_managementFee);
        console.log("should set the leverage threshold max limit when called by governance");
        uint256 _newVal = sut.leverageThresholdMaxCap();
        assertEq(_newVal, _managementFee);
    }

    function testSetter_setLeverageThresholdMaxCap_RevertInvalidAccess() public {
        console.log("ID: Fa_SLTMa_2");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setLeverageThresholdMaxCap(_managementFee);
    }

    function testSetter_setLeverageThresholdMaxCap_RevertInvalidValue() public {
        console.log("ID: Fa_SLTMa_3");
        console.log("should revert if new leverageThresholdMax is greater than leverageThresholdMin");
        uint256 levThresholdMin = sut.leverageThresholdMinCap();
        uint256 newLevThresholdMax = levThresholdMin + 1;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_LEV_THRESH_MAX));
        admin.setLeverageThresholdMaxCap(newLevThresholdMax);
    }

    function testSetter_setMinimumTrancheDuration_Success() public {
        console.log("ID: Fa_SMiTD_1");
        console.log("should emit TrancheDurationMinUpdated when called by governance");
        vm.expectEmit(true, true, true, true);
        emit TrancheDurationMinUpdated(_managementFee);
        admin.setMinimumTrancheDuration(_managementFee);
        console.log("should set the min tranche duration when called by governance");
        uint256 _newVal = sut.trancheDurationMin();
        assertEq(_newVal, _managementFee);
    }

    function testSetter_setMinimumTrancheDuration_RevertInvalidAccess() public {
        console.log("ID: Fa_SMiTD_2");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setMinimumTrancheDuration(_managementFee);
    }

    function testSetter_setMinimumTrancheDuration_RevertInvalidValue() public {
        console.log("ID: Fa_SMiTD_3");
        console.log("should revert with error VE_INVALID_ZERO_VALUE if set to zero value by governance role account");
        uint256 newMinTrancheDuration; // 0
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ZERO_VALUE));
        admin.setMinimumTrancheDuration(newMinTrancheDuration);
    }

    function testSetter_setMaximumTrancheDuration_Success() public {
        console.log("ID: Fa_SMaTD_1");
        console.log("should emit TrancheDurationMaxUpdated when called by governance");
        vm.expectEmit(true, true, true, true);
        emit TrancheDurationMaxUpdated(_managementFee);
        admin.setMaximumTrancheDuration(_managementFee);
        console.log("should set the max tranche duration when called by governance");
        uint256 _newVal = sut.trancheDurationMax();
        assertEq(_newVal, _managementFee);
    }

    function testSetter_setMaximumTrancheDuration_RevertInvalidAccess() public {
        console.log("ID: Fa_SMaTD_2");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setMaximumTrancheDuration(_managementFee);
    }

    function testSetter_setMaximumTrancheDuration_RevertInvalidValue() public {
        console.log("ID: Fa_SMaTD_3");
        console.log("should revert with error VE_INVALID_ZERO_VALUE if set to zero value by governance role account");
        uint256 newMaxTrancheDuration; // 0
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ZERO_VALUE));
        admin.setMaximumTrancheDuration(newMaxTrancheDuration);
    }

    function testSetter_setMaximumTrancheDuration_RevertInvalidTrancheDuration() public {
        console.log("ID: Fa_SMaTD_4");
        console.log(
            "should revert with error VE_INVALID_TRANCHE_DURATION_MAX if new max tranche duration is less than min tranche duration"
        );
        uint256 newMaxTrancheDuration = sut.trancheDurationMin() - 1;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_DURATION_MAX));
        admin.setMaximumTrancheDuration(newMaxTrancheDuration);
    }

    function testSetter_setTrancheCapacity_Success() public {
        console.log("ID: Fa_STC_1");
        console.log("should emit TrancheCapacityUpdated when called by governance");
        uint256 _newCapacity = sut.minimumInitialDepositUSD() + 1;
        vm.expectEmit(true, false, false, false);
        emit TrancheCapacityUpdated(_newCapacity);
        admin.setTrancheCapacity(_newCapacity);
        console.log("should set the max tranche capacity when called by governance");
        uint256 _newVal = sut.trancheCapacityUSD();
        assertEq(_newVal, _newCapacity);
    }

    function testSetter_setTrancheCapacity_RevertInvalidAccess() public {
        console.log("ID: Fa_STC_2");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setTrancheCapacity(_managementFee);
    }

    function testSetter_setTrancheCapacity_RevertInvalidTrancheCap() public {
        console.log("ID: Fa_STC_3");
        console.log("should revert with VE_INVALID_TRANCHE_CAP if new tranche capacity is 0");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_CAP));
        uint256 _capacityZero;
        admin.setTrancheCapacity(_capacityZero);
    }

    function testSetter_setTrancheCapacity_RevertInvalidTrancheCap_BelowMinDepositVal() public {
        console.log("ID: Fa_STC_4");
        console.log("new trancheCapacity is set to value below minimumDepositValue by GOVERNANCE ROLE");
        uint256 minDepositVal = sut.minimumInitialDepositUSD();
        uint256 capacityUnderMinDepositVal = minDepositVal - 1;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_TRANCHE_CAP));
        admin.setTrancheCapacity(capacityUnderMinDepositVal);
    }

    function testSetter_setFEYProductImplementation_Success() public {
        console.log("ID: Fa_SFPI_1");
        console.log("should emit FEYProductImplementationUpdated when called by governance");
        address nextProductImpl = getNextAddress();
        address oldProductImpl = sut.feyProductImplementation();
        vm.expectEmit(true, true, true, true);
        emit FEYProductImplementationUpdated(oldProductImpl, nextProductImpl);
        admin.setFEYProductImplementation(nextProductImpl);
        console.log("should set the new product implementation address when called by governance");
        address newProductImpl = sut.feyProductImplementation();
        assertEq(newProductImpl, nextProductImpl);
    }

    function testSetter_setFEYProductImplementation_RevertInvalidAccess() public {
        console.log("ID: Fa_SFPI_2");
        console.log("should revert if called by non-governance role account");
        address newProductImpl = getNextAddress();
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setFEYProductImplementation(newProductImpl);
    }

    function testSetter_setFEYProductImplementation_RevertInvalidZeroAddress() public {
        console.log("ID: Fa_SFPI_3");
        console.log(
            "should revert with error VE_INVALID_ZERO_ADDRESS if product impl address is set to zero by governance role account"
        );
        address newProductImpl = address(0);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ZERO_ADDRESS));
        admin.setFEYProductImplementation(newProductImpl);
    }

    function testSetter_setStructPriceOracle_Success() public {
        console.log("ID: Fa_SSPO_1");
        console.log("should emit StructPriceOracleUpdated when called by governance");
        address[] memory assets;
        AggregatorV3Interface[] memory sources;
        IStructPriceOracle nextPriceOracle = new StructPriceOracle(assets, sources);
        vm.expectEmit(true, true, true, true);
        emit StructPriceOracleUpdated(address(nextPriceOracle));
        admin.setStructPriceOracle(nextPriceOracle);
        console.log("should set the price oracle when called by governance");
        IStructPriceOracle _newPriceOracle = sut.structPriceOracle();
        assertEq(address(_newPriceOracle), address(nextPriceOracle));
    }

    function testSetter_setStructPriceOracle_RevertInvalidAccess() public {
        console.log("ID: Fa_SSPO_2");
        console.log("should revert if called by non-governance role account");
        address[] memory assets;
        AggregatorV3Interface[] memory sources;
        IStructPriceOracle nextPriceOracle = new StructPriceOracle(assets, sources);
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setStructPriceOracle(nextPriceOracle);
    }

    function testSetter_setStructPriceOracle_RevertInvalidZeroAddress() public {
        console.log("ID: Fa_SSPO_3");
        console.log("should revert if structPriceOracle is set to zero address by non-governance role account");
        IStructPriceOracle nextPriceOracle = IStructPriceOracle(address(0));
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ZERO_ADDRESS));
        admin.setStructPriceOracle(nextPriceOracle);
    }

    function testSetter_setMinimumDepositValue_Success() public {
        console.log("ID: Fa_SMiDV_1");
        console.log("should emit MinimumInitialDepositValueUpdated when called by governance");
        vm.expectEmit(true, true, true, true);
        emit MinimumInitialDepositValueUpdated(_managementFee);
        admin.setMinimumDepositValueUSD(_managementFee);
        console.log("should set minimum initial deposit value when called by governance");
        uint256 _newVal = sut.minimumInitialDepositUSD();
        assertEq(_newVal, _managementFee);
    }

    function testSetter_setMinimumDepositValue_RevertInvalidAccess() public {
        console.log("ID: Fa_SMiDV_3");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setMinimumDepositValueUSD(_managementFee);
    }

    function testSetter_setMinimumDepositValue_RevertMinDepositValue() public {
        console.log("ID: Fa_SMiDV_2");
        console.log("should revert with VE_MIN_DEPOSIT_VALUE if new min deposit value is 0");
        vm.expectRevert(abi.encodePacked(Errors.VE_MIN_DEPOSIT_VALUE));
        uint256 _capacityZero;
        admin.setMinimumDepositValueUSD(_capacityZero);
    }

    function testSetter_setMinimumDepositValue_RevertMinDepositValue_OverTrancheCap() public {
        console.log("ID: Fa_SMiDV_4");
        console.log(
            "should revert if new minimumDepositValue is set to value greater than trancheCapacity by GOVERNANCE ROLE"
        );
        uint256 trancheCap = sut.trancheCapacityUSD();
        uint256 newMinimumOverTrancheCap = trancheCap + 1;
        vm.expectRevert(abi.encodePacked(Errors.VE_MIN_DEPOSIT_VALUE));
        admin.setMinimumDepositValueUSD(newMinimumOverTrancheCap);
    }

    function testSetter_setMaxFixedRate_Success() public {
        console.log("ID: Fa_SMFR_1");
        console.log("should succeed if maxFixedRate is set by governance role");
        uint256 newMaxFixedRate = 1_000_000; // 100%
        admin.setMaxFixedRate(newMaxFixedRate);
        uint256 fixedRateSet = admin.getMaxFixedRate();
        assertEq(fixedRateSet, newMaxFixedRate);
    }

    function testSetter_setMaxFixedRate_RevertInvalidAccess() public {
        console.log("ID: Fa_SMFR_2");
        console.log("should revert if called by non-governance role account");
        uint256 newMaxFixedRate = 1_000_000; // 100%
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setMaxFixedRate(newMaxFixedRate);
    }

    function testSetter_setMaxFixedRate_RevertInvalidRate() public {
        console.log("ID: Fa_SMFR_3");
        console.log("should revert if maxFixedRate is set to zero by governance role");
        uint256 newMaxFixedRate = 0;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_RATE));
        admin.setMaxFixedRate(newMaxFixedRate);
    }

    function testSetter_setYieldSource_Success() public {
        console.log("ID: GMX_Fa_SYS_1");
        console.log("should set the yield source address when called by governance");
        admin.setYieldSource(address(yieldSource));
        IGMXYieldSource _newYieldSource = sut.yieldSource();
        assertEq(address(_newYieldSource), address(yieldSource));
    }

    function testSetter_setYieldSource_RevertInvalidAccess() public {
        console.log("ID: GMX_Fa_SYS_2");
        console.log("should revert if called by non-governance role account");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setYieldSource(address(yieldSource));
    }

    function testSetter_setYieldSource_RevertIfInvalidAddress() public {
        console.log("should revert if input address is ZeroAddress");
        vm.expectRevert(abi.encodePacked(Errors.AE_ZERO_ADDRESS));
        admin.setYieldSource(address(0));
    }

    function testSetter_setPoolStatus_Success() public {
        console.log("ID: Fa_SPS_1");
        console.log("token0 and token1 are emitted from setPoolStatus by GOVERNANCE ROLE");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(true));
        vm.expectEmit(true, true, true, true);
        emit PoolStatusUpdated(address(GMX_VAULT), 1, address(wavax), address(usdc));
        admin.setPoolStatus(address(wavax), address(usdc));
    }

    function testSetter_setPoolStatus_RevertInvalidAccess() public {
        console.log("ID: Fa_SPS_2");
        console.log("setPoolStatus reverts with error ACE_INVALID_ACCESS when called by NON GOVERNANCE ROLE");
        vm.mockCall(address(GMX_VAULT), abi.encodeWithSelector(IGMXVault.whitelistedTokens.selector), abi.encode(true));
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setPoolStatus(address(wavax), address(usdc));
    }

    function testSetter_const_EmitEvent_FactoryGACInit() public {
        console.log("ID: Fa_const_1");
        console.log("should emit FactoryGACInitialized when initialized");
        vm.expectEmit(true, true, true, true);
        emit FactoryGACInitialized(address(gac));
        sut = new FEYFactoryHarness(
            ISPToken(address(spToken)),
            address(productImpl),
            IGAC(address(gac)),
            IStructPriceOracle(address(oracle)),
            IERC20Metadata(address(wavax)),
            IDistributionManager(distributionManager)
        );
    }
}
