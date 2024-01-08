pragma solidity 0.8.11;

import "@interfaces/IGMXYieldSource.sol";
import "@interfaces/IDistributionManager.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@core/libraries/helpers/Constants.sol";

import "../../../common/fey-products/gmx/GMXProductBaseTestSetupLive.sol";

contract FGMXPRemoveFunds_IntegrationTest is GMXProductBaseTestSetupLive {
    DataTypes.ProductConfig private productConfig;
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    uint256 private wavaxToBeInvested = 112e18;
    uint256 private usdcToBeInvested = 1351e6;

    uint256 private usdcValueDecimalsScalingFactor = 10 ** 12;

    // amounts returned from redeemTokens()
    uint256 private wavaxToBeRedeemed = 100000019025875190286;
    uint256 private usdcToBeRedeemed = 1202296143;
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

        srFrFactor = sut.srFrFactor_exposed(fixedRate, trancheDuration, wavaxToDeposit);
        makeInitialDeposits();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        investTestsFixture(wavax, usdc, 1000e18, 20000e18);
        setGMXProductInfo(wavax, usdc);
    }

    function makeInitialDeposits() internal {
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, JUNIOR_TRANCHE, usdc);
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

    function testForkRemoveFundsFromLP_RevertIfAlreadyRemoved() public {
        DataTypes.FEYGMXProductInfo memory _productInfo = yieldSource.getFEYGMXProductInfo(address(sut));
        console.log("productInfo tokenA", _productInfo.tokenADecimals);
        console.log(
            "should revert with VE_INVALID_STATE (code '22') when tried to call removeFundsFromLP() if already removed"
        );
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.removeFundsFromLP();
    }

    function testForkRemoveFundsFromLP_RevertIfNotMatured() public {
        console.log(
            "should revert with VE_NOT_MATURED (code '24') when tried to call removeFundsFromLP() before maturity"
        );
        _warpAndMockDMCalls();
        user1.invest();
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.redeemTokens.selector),
            abi.encode(wavaxToBeRedeemed, usdcToBeRedeemed)
        );
        vm.expectRevert(abi.encodePacked(Errors.VE_NOT_MATURED));
        user1.removeFundsFromLP();
    }

    function testForkRemoveFundsFromLP_ShouldUpdateProductStatus() public {
        console.log("should update the status of the product to `WITHDRAWN`");
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();
        assert(sut.getCurrentState() == DataTypes.State.WITHDRAWN);
    }

    function testForkRemoveFundsFromLP_ShouldEmitStatusUpdatedEvent() public {
        console.log("should emit `StatusUpdated()` event");

        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        vm.expectEmit(true, false, false, true, address(sut));
        emit StatusUpdated(DataTypes.State.WITHDRAWN);

        user1.removeFundsFromLP();
    }

    function testForkRemoveFundsFromLP_tokensReceivedFromLP() public {
        console.log("should receive the correct amount of tokens from LP");

        vm.warp(block.timestamp + 15 minutes);
        user1.invest();

        uint256 _productBalUSDCPostInvest = usdc.balanceOf(address(sut));

        vm.warp(block.timestamp + 60 minutes);

        vm.mockCall(address(distributionManager), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
        user1.removeFundsFromLP();

        uint256 _performanceFeeAccrued =
            ((wavaxToBeRedeemed - wavaxToDeposit) * performanceFee) / Constants.DECIMAL_FACTOR;

        assertEq(
            wavax.balanceOf(address(sut)),
            wavaxToBeRedeemed - _performanceFeeAccrued,
            "product wAVAX balance post withdraw"
        );

        // factor in excess tokens with _productBalUSDCPostInvest
        assertEq(
            usdc.balanceOf(address(sut)) - _productBalUSDCPostInvest,
            usdcToBeRedeemed,
            "product USDC balance post withdraw"
        );
    }

    function testFailForkRemoveFundsFromLP_ShouldNotEmitPerformanceFeeSentEvent() public {
        console.log("should not emit `PerformanceFeeSent()` event when there is no profits");

        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        vm.expectEmit(true, true, true, true, address(sut));
        emit PerformanceFeeSent(
            SENIOR_TRANCHE, ((srFrFactor - wavaxToDeposit) * performanceFee) / Constants.DECIMAL_FACTOR
        );
        user1.removeFundsFromLP();
    }

    /// MANAGEMENT FEE IS CURRENTLY DISABLED

    // function testForkRemoveFundsFromLP_ShouldEmitManagementFeeSentEvent_SeniorTranche() public {
    //     console.log("should emit `ManagementFeeSent()` event for the senior tranche");

    //     _warpAndMockDMCalls();
    //     user1.invest();

    //     vm.warp(block.timestamp + 60 minutes);
    //     vm.expectEmit(true, true, true, true, address(sut));
    //     emit ManagementFeeSent(
    //         SENIOR_TRANCHE,
    //         (wavaxToDeposit * managementFee) / Constants.DECIMAL_FACTOR
    //     );
    //     user1.removeFundsFromLP();
    // }

    /// MANAGEMENT FEE IS CURRENTLY DISABLED

    // function testForkRemoveFundsFromLP_ShouldEmitManagementFeeSentEvent_JuniorTranche() public {
    //     console.log("should emit `ManagementFeeSent()` event for the junior tranche");
    //     _warpAndMockDMCalls();
    //     user1.invest();
    //     DataTypes.TrancheInfo memory _jrTrancheInfo = sut.getTrancheInfo(JUNIOR_TRANCHE);

    //     uint256 expectedFee = ((_jrTrancheInfo.tokensInvestable) * managementFee) /
    //         Constants.DECIMAL_FACTOR;
    //     vm.warp(block.timestamp + 60 minutes);
    //     vm.expectEmit(true, true, true, true, address(sut));
    //     emit ManagementFeeSent(JUNIOR_TRANCHE, expectedFee);
    //     user1.removeFundsFromLP();
    // }

    function testForkRemoveFundsFromLP_ShouldUpdateSeniorFeeTotal() public {
        console.log("should update the total senior fee accrued");

        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        uint256 _performanceFeeAccrued =
            ((wavaxToBeRedeemed - wavaxToDeposit) * performanceFee) / Constants.DECIMAL_FACTOR;

        /// MANAGEMENT FEE IS CURRENTLY DISABLED
        uint256 _managementFeeAccrued = 0;

        user1.removeFundsFromLP();

        assertEq(sut.feeTotalSr(), _performanceFeeAccrued + _managementFeeAccrued);
    }

    function testForkRemoveFundsFromLP_ShouldUpdateJuniorFeeTotal() public {
        console.log("should update the total junior fee accrued");

        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();
        /// MANAGEMENT FEE IS CURRENTLY DISABLED
        uint256 _managementFeeAccrued = 0;

        assertEq(sut.feeTotalJr(), _managementFeeAccrued);
    }

    function testForkRemoveFundsFromLP_ShouldTransferFeeInWAVAX() public {
        console.log("should swap and transfer fee to the distribution manager in wAVAX");
        _warpAndMockDMCalls();
        user1.invest();

        uint256 wavaxBalanceBefore = wavax.balanceOf(distributionManager);
        uint256 usdcBalanceBefore = usdc.balanceOf(distributionManager);

        vm.warp(block.timestamp + 60 minutes);
        uint256 _jrToSrRate = sut.getTokenRate(SENIOR_TRANCHE);

        user1.removeFundsFromLP();
        uint256 wavaxBalanceAfter = wavax.balanceOf(distributionManager);
        uint256 usdcBalanceAfter = usdc.balanceOf(distributionManager);

        uint256 allowedDelta = 0.01e18; //0.01%

        assertApproxEqRel(
            sut.feeTotalSr() + (sut.feeTotalJr() * Constants.WAD) / _jrToSrRate,
            wavaxBalanceAfter - wavaxBalanceBefore,
            allowedDelta
        );

        assertEq(usdcBalanceBefore, usdcBalanceAfter, "usdcBalance");
    }
}
