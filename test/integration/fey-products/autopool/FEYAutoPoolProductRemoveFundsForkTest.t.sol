pragma solidity 0.8.11;

import "@interfaces/IDistributionManager.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Constants.sol";
import {ILBRouter} from "@external/traderjoe/ILBRouter.sol";

import "../../../common/fey-products/autopool/AutoPoolProductBaseTestSetupLive.sol";

contract FEYAutoPoolProductRemoveFunds_IntegrationTest is AutoPoolProductBaseTestSetupLive {
    error BaseVault__ZeroShares();

    DataTypes.ProductConfig private productConfig;
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    uint256 private wavaxToBeInvested = 100e18;
    uint256 private usdcToBeInvested = 1606e6;

    uint256 private usdcValueDecimalsScalingFactor = 10 ** 12;

    // amounts returned from redeemTokens()
    uint256 private wavaxToBeRedeemed = wavaxToDeposit + 5e18; // accrue rewards
    uint256 private usdcToBeRedeemed = usdcToBeInvested + 100e6; // accrue rewards
    uint256 private trancheDuration;

    uint256 private srFrFactor;

    event StatusUpdated(DataTypes.State currentStatus);
    event PerformanceFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);
    event ManagementFeeSent(DataTypes.Tranche _tranche, uint256 _tokensSent);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 33646790);

        super.setUp();

        productConfig = sut.getProductConfig();
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);
        makeInitialDeposits();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        uint256 _investmentTerm = 20 minutes;
        investTestsFixture(wavax, usdc, 1000e18, 20000e18, _investmentTerm);
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

    function testForkRemoveFundsFromLP_ShouldUpdateIsQueuedFlag() public {
        console.log("APPr_RFFLP_1: should set the `isQueuedForWithdrawal` to 1");
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        assertEq(sut.isQueuedForWithdrawal(), 1);
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case1() public {
        console.log("Pr_RFFLP_16: should swap the excess received senior tranche tokens to junior tranche tokens");
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor + 5e18;

        uint256 _jrReceived = usdcToBeInvested;

        deal(address(wavax), address(sut), _srReceived);
        deal(address(usdc), address(sut), _jrReceived);
        (uint256 _amountSwapped, DataTypes.Tranche _trancheSwappedFrom) =
            sut.allocateToTranches_exposed(_srReceived, _jrReceived * usdcValueDecimalsScalingFactor, srFrFactor);
        assertEq(_amountSwapped, _srReceived - srFrFactor, "amountSwapped");
        assertEq(uint8(_trancheSwappedFrom), uint8(SENIOR_TRANCHE), "trancheSwappedFrom");
        assertGt(usdc.balanceOf(address(sut)), usdcToBeInvested, "swappedToJuniorTranche");
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case2() public {
        console.log(
            "Pr_RFFLP_19: should swap all the received junior tranche tokens to fill the expected to senior tranche tokens"
        );
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);
        uint256 _srReceived = srFrFactor - 5e18;

        uint256 _jrReceived = 55e6;

        deal(address(wavax), address(sut), _srReceived);
        deal(address(usdc), address(sut), _jrReceived);

        (uint256 _amountSwapped, DataTypes.Tranche _trancheSwappedFrom) =
            sut.allocateToTranches_exposed(_srReceived, _jrReceived * usdcValueDecimalsScalingFactor, srFrFactor);

        assertEq(_amountSwapped, _jrReceived * usdcValueDecimalsScalingFactor, "amountSwapped");
        assertEq(uint8(_trancheSwappedFrom), uint8(JUNIOR_TRANCHE), "trancheSwappedFrom");
        assertGt(wavax.balanceOf(address(sut)), _srReceived, "swappedToSeniorTranche");
        assertEq(usdc.balanceOf(address(sut)), 0, "swappedAllJuniorTrancheTokens");
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case3() public {
        console.log(
            "Pr_RFFLP_18: should swap a part of the received junior tranche tokens to fill the expected to senior tranche tokens"
        );
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);
        uint256 _srReceived = srFrFactor - 5e18;

        uint256 _jrReceived = 100e6;

        deal(address(wavax), address(sut), _srReceived);
        deal(address(usdc), address(sut), _jrReceived);

        (, uint256 _rate,,) = sut.getTokenRate(JUNIOR_TRANCHE, srFrFactor - _srReceived);

        (uint256 _amountSwapped, DataTypes.Tranche _trancheSwappedFrom) =
            sut.allocateToTranches_exposed(_srReceived, _jrReceived * usdcValueDecimalsScalingFactor, srFrFactor);

        uint256 _expectedAmountToBeSwapped = (srFrFactor - _srReceived) * Constants.WAD / _rate;
        assertEq(_amountSwapped, _expectedAmountToBeSwapped, "amountSwapped");
        assertEq(uint8(_trancheSwappedFrom), uint8(JUNIOR_TRANCHE), "trancheSwappedFrom");
        assertLt(usdc.balanceOf(address(sut)), _jrReceived, "juniorTrancheTokensSwapped");
        assertApproxEqRel(srFrFactor, wavax.balanceOf(address(sut)), 0.001e18, "expectedSeniorTokens == productBalance"); // 0.01%
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case4() public {
        console.log(
            "Pr_RFFLP_17: total senior tranche tokens recieved is equal to the senior tranche fixed-rate factor - no swaps required"
        );
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor;

        uint256 _jrReceived = 100e6;

        deal(address(wavax), address(sut), _srReceived);
        deal(address(usdc), address(sut), _jrReceived);

        (uint256 _amountSwapped,) =
            sut.allocateToTranches_exposed(_srReceived, _jrReceived * usdcValueDecimalsScalingFactor, srFrFactor);

        assertEq(_amountSwapped, 0, "amountSwapped");
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case5() public {
        console.log("Should successfully execute swap when the senior tranche delta is very small");
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);
        uint256 _srReceived = srFrFactor - 1;

        uint256 _jrReceived = 55e6;

        deal(address(wavax), address(sut), _srReceived);
        deal(address(usdc), address(sut), _jrReceived);

        vm.expectCall(address(sut.lbRouter()), abi.encodeWithSelector(ILBRouter.swapTokensForExactTokens.selector));

        sut.allocateToTranches_exposed(_srReceived, _jrReceived * usdcValueDecimalsScalingFactor, srFrFactor);
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case6() public {
        console.log("if _jrReceived is more than _jrToSwap but less than _amountIn, should swap all junior tokens");
        console.log("this is preventing the swapToExact call to fail due to insufficient junior tokens in");
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);
        uint256 _srReceived = srFrFactor - 1e17;

        // more than _jrToSwap but less than _amountIn
        uint256 _jrReceived = 1_248_000;

        deal(address(wavax), address(sut), _srReceived);
        deal(address(usdc), address(sut), _jrReceived);

        vm.expectCall(address(sut.lbRouter()), abi.encodeWithSelector(ILBRouter.swapExactTokensForTokens.selector));

        sut.allocateToTranches_exposed(_srReceived, _jrReceived * usdcValueDecimalsScalingFactor, srFrFactor);
    }

    function testForkRemoveFundsFromLP_allocateToTranches_Case7() public {
        console.log(
            "successfully calls swapTokensForExactTokens when senior tokens received < srFrFactor and senior decimals != 18"
        );
        uint256 _investmentTerm = 20 minutes;
        investTestsFixture(usdc, wavax, 20000e18, 1000e18, _investmentTerm);
        grantRoles();
        _deposit(user1, usdcToDeposit, SENIOR_TRANCHE, usdc);
        _deposit(user2, wavaxToDeposit, JUNIOR_TRANCHE, wavax);
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);
        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceivedWei = srFrFactor - 50e18;
        uint256 _srReceivedTokenDecimals = _srReceivedWei / usdcValueDecimalsScalingFactor;

        uint256 _jrReceivedWei = 100e18;

        deal(address(usdc), address(sut), _srReceivedTokenDecimals);
        deal(address(wavax), address(sut), _jrReceivedWei);

        vm.expectCall(address(sut.lbRouter()), abi.encodeWithSelector(ILBRouter.swapTokensForExactTokens.selector));
        sut.allocateToTranches_exposed(_srReceivedWei, _jrReceivedWei, srFrFactor);
    }

    function testForkRemoveFundsFromLPSansRecompound() public {
        console.log(
            "when recompoundRewards reverts with error `BaseVault__ZeroShares`, should catch error and call queueForRedemptionSansRecompound successfully"
        );
        uint256 _investmentTerm = 20 minutes;
        investTestsFixture(usdc, wavax, 20000e18, 1000e18, _investmentTerm);
        grantRoles();
        /// about $0.01
        uint256 _usdcToDeposit = 10 ** 4;
        /// about $0.01
        uint256 _wavaxToDeposit = 10 ** 15;
        _deposit(user1, _usdcToDeposit, SENIOR_TRANCHE, usdc);
        _deposit(user2, _wavaxToDeposit, JUNIOR_TRANCHE, wavax);
        _warpAndMockDMCalls();
        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        vm.prank(address(keeper));
        vm.expectRevert(abi.encodeWithSelector(BaseVault__ZeroShares.selector));
        yieldSource.recompoundRewards();

        vm.expectCall(
            address(yieldSource), abi.encodeWithSelector(IAutoPoolYieldSource.queueForRedemptionSansRecompound.selector)
        );
        sut.removeFundsFromLP();
    }

    function testForkRemoveFundsFromLP_ShouldUpdateFeeTotal() public {
        console.log("Pr_RFFLP_26: should update the total fee accrued");

        _warpAndMockDMCalls();

        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor + 5e18;

        uint256 _jrReceived = usdcToBeRedeemed;
        deal(address(wavax), address(yieldSource), _srReceived);
        deal(address(usdc), address(yieldSource), _jrReceived);

        vm.startPrank(address(yieldSource));

        wavax.approve(address(sut), _srReceived);
        usdc.approve(address(sut), _jrReceived);

        sut.processRedemption(_srReceived, _jrReceived);

        vm.stopPrank();
        DataTypes.TrancheInfo memory _seniorTrancheInfo = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _juniorTrancheInfo = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 _seniorPerformanceFeeAccrued =
            ((_srReceived - _seniorTrancheInfo.tokensInvestable) * performanceFee) / Constants.DECIMAL_FACTOR;
        uint256 _juniorPerformanceFeeAccrued = (
            (_jrReceived * usdcValueDecimalsScalingFactor - _juniorTrancheInfo.tokensInvestable) * performanceFee
        ) / Constants.DECIMAL_FACTOR;

        assertEq(sut.feeTotalSr(), _seniorPerformanceFeeAccrued);
        assertEq(sut.feeTotalJr(), _juniorPerformanceFeeAccrued);
    }

    function testForkRemoveFundsFromLP_ShouldTransferFeeInWAVAX() public {
        console.log("Pr_RFFLP_15: should swap and transfer fee to the distribution manager in wAVAX");
        _warpAndMockDMCalls();

        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor + 5e18;

        uint256 _jrReceived = usdcToBeRedeemed;

        uint256 wavaxBalanceBefore = wavax.balanceOf(distributionManager);
        uint256 usdcBalanceBefore = usdc.balanceOf(distributionManager);

        vm.warp(block.timestamp + 60 minutes);
        (, uint256 _jrToSrRate,,) = sut.getTokenRate(SENIOR_TRANCHE, 0);

        deal(address(wavax), address(yieldSource), _srReceived);
        deal(address(usdc), address(yieldSource), _jrReceived);

        vm.startPrank(address(yieldSource));

        wavax.approve(address(sut), _srReceived);
        usdc.approve(address(sut), _jrReceived);

        sut.processRedemption(_srReceived, _jrReceived);

        vm.stopPrank();

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

    function testForkRemoveFundsFromLP_RevertIfAlreadyRedeemed() public {
        console.log(
            "should revert with VE_INVALID_STATE (code '22') when tried to call processRedemption() if already processed"
        );
        _warpAndMockDMCalls();

        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor + 5e18;

        uint256 _jrReceived = usdcToBeRedeemed;

        deal(address(wavax), address(yieldSource), _srReceived);
        deal(address(usdc), address(yieldSource), _jrReceived);

        vm.startPrank(address(yieldSource));

        wavax.approve(address(sut), _srReceived);
        usdc.approve(address(sut), _jrReceived);

        sut.processRedemption(_srReceived, _jrReceived);

        vm.stopPrank();

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        vm.prank(address(yieldSource));
        sut.processRedemption(_srReceived, _jrReceived);
    }

    function testForkRemoveFundsFromLP_ShouldUpdateProductStatus() public {
        console.log("Pr_RFFLP_27: should update the status of the product to `WITHDRAWN`");
        _warpAndMockDMCalls();

        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor + 5e18;

        uint256 _jrReceived = usdcToBeRedeemed;

        deal(address(wavax), address(yieldSource), _srReceived);
        deal(address(usdc), address(yieldSource), _jrReceived);

        vm.startPrank(address(yieldSource));

        wavax.approve(address(sut), _srReceived);
        usdc.approve(address(sut), _jrReceived);

        sut.processRedemption(_srReceived, _jrReceived);

        vm.stopPrank();

        assert(sut.getCurrentState() == DataTypes.State.WITHDRAWN);
    }

    function testForkRemoveFundsFromLP_ShouldUpdateIsQueuedFlagAfterRedemption() public {
        console.log("APPr_RFFLP_2: should set `isQueuedForWithdrawal` flag to 2 after redemption");
        _warpAndMockDMCalls();

        user1.invest();

        vm.warp(block.timestamp + 60 minutes);

        user1.removeFundsFromLP();

        trancheDuration = productConfig.endTimeTranche - productConfig.startTimeTranche;

        srFrFactor = sut.srFrFactor_exposed(trancheDuration);

        uint256 _srReceived = srFrFactor + 5e18;

        uint256 _jrReceived = usdcToBeRedeemed;

        deal(address(wavax), address(yieldSource), _srReceived);
        deal(address(usdc), address(yieldSource), _jrReceived);

        vm.startPrank(address(yieldSource));
        wavax.approve(address(sut), _srReceived);
        usdc.approve(address(sut), _jrReceived);
        sut.processRedemption(_srReceived, _jrReceived);

        vm.stopPrank();
        assertEq(sut.isQueuedForWithdrawal(), 2);
    }
}
