pragma solidity 0.8.11;

import "@interfaces/IGMXYieldSource.sol";
import "@interfaces/IDistributionManager.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@core/libraries/helpers/Constants.sol";

import "../../../common/fey-products/gmx/GMXProductBaseTestSetupLive.sol";

contract FGMXPRemoveFundsSameToken_IntegrationTest is GMXProductBaseTestSetupLive {
    DataTypes.ProductConfig private productConfig;
    uint256 public usdcToDepositSr = 2000e6;
    uint256 public usdcToDepositJr = 2000e6;

    uint256 private usdcValueDecimalsScalingFactor = 10 ** 12;

    // amounts returned from redeemTokens()
    uint256 private usdcSrToBeRedeemed = 2000000376;
    uint256 private usdcJrToBeRedeemed = 1555311164;
    uint256 private trancheDuration;

    uint256 private srFrFactor;

    event StatusUpdated(DataTypes.State currentStatus);
    event PerformanceFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);
    event ManagementFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 24540193);

        super.setUp();

        productConfig = sut.getProductConfig();
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(fixedRate, trancheDuration, usdcToDepositSr);
        makeInitialDeposits();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        investTestsFixture(usdc, usdc, 20000e18, 20000e18);
        setGMXProductInfo(usdc, usdc);
    }

    function makeInitialDeposits() internal {
        _deposit(user1, usdcToDepositSr, SENIOR_TRANCHE, usdc);
        _deposit(user2, usdcToDepositJr, JUNIOR_TRANCHE, usdc);
    }

    function _warpAndMockDMCalls() internal {
        vm.warp(block.timestamp + 15 minutes);

        // Mock call to Distribution manager
        vm.mockCall(
            address(distributionManager),
            abi.encodeWithSelector(IDistributionManager.queueFees.selector),
            abi.encode(true)
        );
    }

    function testForkRemoveFundsFromLP_tokensReceivedFromLP() public {
        console.log("should receive the correct amount of tokens from LP");

        vm.warp(block.timestamp + 15 minutes);
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        vm.mockCall(address(distributionManager), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
        user1.removeFundsFromLP();

        DataTypes.TrancheInfo memory _trancheSrInfo = sut.getTrancheInfo(SENIOR_TRANCHE);
        assertEq(
            _trancheSrInfo.tokensAtMaturity / usdcValueDecimalsScalingFactor,
            usdcSrToBeRedeemed,
            "product USDC Sr tokensAtMaturity post withdraw"
        );
        DataTypes.TrancheInfo memory _trancheJrInfo = sut.getTrancheInfo(JUNIOR_TRANCHE);
        assertEq(
            _trancheJrInfo.tokensAtMaturity / usdcValueDecimalsScalingFactor,
            usdcJrToBeRedeemed,
            "product USDC Jr tokensAtMaturity post withdraw"
        );
    }

    function testFailForkRemoveFundsFromLP_ShouldNotEmitPerformanceFeeSentEvent() public {
        console.log("should not emit `PerformanceFeeSent()` event when there is no profits");

        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        vm.expectEmit(true, true, true, true, address(sut));
        emit PerformanceFeeSent(
            SENIOR_TRANCHE, ((srFrFactor - usdcToDepositSr) * performanceFee) / Constants.DECIMAL_FACTOR
        );
        user1.removeFundsFromLP();
    }
}
