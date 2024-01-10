// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "../../common/rewarder/RewarderBaseTestSetup.sol";
import "@core/libraries/helpers/Constants.sol";
import "@interfaces/IFEYProduct.sol";

contract RewarderAllocateRewards_UnitTest is RewarderBaseTestSetup {
    event RewardAllocated(
        address indexed product, address indexed reward, uint256 rewardSr, uint256 rewardJr, bool immediateDistribution
    );

    function onSetup() public virtual override {
        depositInvestTestsFixture(true);
    }

    function testAllocateRewards_RevertWhenNoRewarderRole() public {
        console.log("ID: R_AR_1");
        console.log("should revert when allocateRewards is called by an address without the REWARDER role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        vm.prank(address(user1));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_RevertWhenNoProductRole() public {
        console.log("ID: R_AR_2");
        console.log(
            "should revert when allocateRewards is called with a product address that does not have a PRODUCT role"
        );
        gac.revokeRole(PRODUCT, address(product));
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_RevertWhenNoAPRInputs() public {
        console.log("ID: R_AR_3");
        console.log("should revert when allocateRewards is called with no APR inputs");
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_INVALID_APR));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), 0, 0, true);
    }

    function testAllocateRewards_RevertWhenZeroAddressUsedForRewardToken() public {
        console.log("ID: R_AR_4");
        console.log("should revert when allocateRewards is called with zero address used for reward token");
        vm.expectRevert(abi.encodePacked(Errors.AE_ZERO_ADDRESS));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(0), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_RevertWhenProductInOpenState() public {
        console.log("ID: R_AR_5");
        console.log("should revert when product being allocated to is in open state");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_RevertWhenProductInWithdrawnState() public {
        console.log("ID: R_AR_6");
        console.log("should revert when product being allocated to is in withdrawn state");
        product.setCurrentState(DataTypes.State.WITHDRAWN);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_RevertWhenRewarderIsPausedLocally() public {
        console.log("ID: R_AR_7");
        console.log("should revert when rewarder is paused locally");
        vm.prank(address(pauser));
        sut.pause();
        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_RevertWhenRewarderIsPausedGlobally() public {
        console.log("ID: R_AR_8");
        console.log("should revert when rewarder is paused globally");
        vm.prank(address(pauser));
        IGAC(address(gac)).pause();
        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }

    function testAllocateRewards_ShouldTransferWAVAXRewardTokenForSrTranche() public {
        console.log("ID: R_AR_9");
        console.log("should transfer WAVAX reward token for senior tranche");
        uint256 _investable = 10000 * Constants.WAD;
        uint256 balanceBefore = IERC20Metadata(address(wavax)).balanceOf(address(sut));
        product.setTokensInvestable(SENIOR_TRANCHE, _investable);
        product.setCurrentState(DataTypes.State.INVESTED);
        uint256 _allocation =
            (srRewardAPR * _investable * DURATION) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);
        deal(address(wavax), rewarder, _allocation);
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), _allocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, 0, true);
        vm.stopPrank();
        uint256 balanceAfter = IERC20Metadata(address(wavax)).balanceOf(address(sut));

        uint256 balanceDiff = balanceAfter - balanceBefore;

        assertEq(balanceDiff, _allocation);
    }

    function testAllocateRewards_ShouldTransferWAVAXRewardTokenForJrTranche() public {
        console.log("ID: R_AR_10");
        console.log("should transfer WAVAX reward token for junior tranche");
        uint256 _investable = 100000 * Constants.WAD;
        uint256 balanceBefore = IERC20Metadata(address(wavax)).balanceOf(address(sut));
        product.setTokensInvestable(JUNIOR_TRANCHE, _investable);
        product.setCurrentState(DataTypes.State.INVESTED);

        /// Oracle price set to 20e18 for wAVAX and 1e18 for USDC
        uint256 _allocation = ((jrRewardAPR * _investable * DURATION * Constants.WAD) / avaxPrice)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        deal(address(wavax), rewarder, _allocation);
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), _allocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), 0, jrRewardAPR, true);
        vm.stopPrank();
        uint256 balanceAfter = IERC20Metadata(address(wavax)).balanceOf(address(sut));

        uint256 balanceDiff = balanceAfter - balanceBefore;

        assertEq(balanceDiff, _allocation);
    }

    function testAllocateRewards_ShouldTransferWAVAXRewardTokenForBothTranches() public {
        console.log("ID: R_AR_11");
        console.log("should transfer WAVAX reward token for both senior and junior tranche");
        uint256 _investableSr = 10000 * Constants.WAD;
        uint256 _investableJr = 100000 * Constants.WAD;
        uint256 balanceBefore = IERC20Metadata(address(wavax)).balanceOf(address(sut));
        product.setTokensInvestable(SENIOR_TRANCHE, _investableSr);
        product.setTokensInvestable(JUNIOR_TRANCHE, _investableJr);
        product.setCurrentState(DataTypes.State.INVESTED);

        /// Oracle price set to 20e18 for wAVAX and 1e18 for USDC
        /// Account for junior allocation
        uint256 _allocation = ((jrRewardAPR * _investableJr * DURATION * Constants.WAD) / avaxPrice)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Account for allocation to senior tranche
        _allocation += (srRewardAPR * _investableSr * DURATION) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        deal(address(wavax), rewarder, _allocation);
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), _allocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();
        uint256 balanceAfter = IERC20Metadata(address(wavax)).balanceOf(address(sut));

        uint256 balanceDiff = balanceAfter - balanceBefore;

        assertEq(balanceDiff, _allocation);
    }

    function testAllocateRewards_ShouldTransferMultipleRewardTokensForBothTranches() public {
        console.log("ID: R_AR_12");
        console.log("should transfer multiple reward tokens for both senior and junior tranche");

        /// Setup product
        uint256 _investableSr = 10000 * Constants.WAD;
        uint256 _investableJr = 100000 * Constants.WAD;
        product.setTokensInvestable(SENIOR_TRANCHE, _investableSr);
        product.setTokensInvestable(JUNIOR_TRANCHE, _investableJr);
        product.setCurrentState(DataTypes.State.INVESTED);

        /// ======== Account for wavax allocation ========

        uint256 balanceBeforeWAVAX = IERC20Metadata(address(wavax)).balanceOf(address(sut));

        /// Account for wavax allocation to junior tranche
        uint256 _allocationWAVAX = ((jrRewardAPR * _investableJr * DURATION * Constants.WAD) / avaxPrice)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Account for wavax allocation to senior tranche
        _allocationWAVAX +=
            (srRewardAPR * _investableSr * DURATION) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Deal wavax reward tokens
        deal(address(wavax), rewarder, _allocationWAVAX);

        /// Call allocateRewards
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), _allocationWAVAX);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();
        uint256 balanceAfterWAVAX = IERC20Metadata(address(wavax)).balanceOf(address(sut));
        uint256 balanceDiffWAVAX = balanceAfterWAVAX - balanceBeforeWAVAX;
        assertEq(balanceDiffWAVAX, _allocationWAVAX);

        /// ======== Account for USDC allocation ========

        uint256 balanceBeforeUSDC = IERC20Metadata(address(usdc)).balanceOf(address(sut));

        uint256 _allocationUSDC =
            ((jrRewardAPR * _investableJr * DURATION) / 1e12) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        _allocationUSDC += ((srRewardAPR * _investableSr * DURATION * avaxPrice) / (Constants.WAD * 1e12))
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Deal usdc reward tokens
        deal(address(usdc), rewarder, _allocationUSDC);

        /// Call allocateRewards
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(usdc)).approve(address(sut), _allocationUSDC);
        sut.allocateRewards(IFEYProduct(address(product)), address(usdc), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();
        uint256 balanceAfterUSDC = IERC20Metadata(address(usdc)).balanceOf(address(sut));
        uint256 balanceDiffUSDC = balanceAfterUSDC - balanceBeforeUSDC;
        assertEq(balanceDiffUSDC, _allocationUSDC);

        /// ======== Account for reward2 allocation ========

        uint256 balanceBeforeReward2 = IERC20Metadata(address(rewardToken2)).balanceOf(address(sut));

        uint256 _allocationReward2 = ((jrRewardAPR * _investableJr * DURATION * Constants.WAD) / reward2Price)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        _allocationReward2 += ((srRewardAPR * _investableSr * DURATION * avaxPrice) / reward2Price)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Deal reward2 reward tokens
        deal(address(rewardToken2), rewarder, _allocationReward2);

        /// Call allocateRewards
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(rewardToken2)).approve(address(sut), _allocationReward2);
        sut.allocateRewards(IFEYProduct(address(product)), address(rewardToken2), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();
        uint256 balanceAfterReward2 = IERC20Metadata(address(rewardToken2)).balanceOf(address(sut));
        uint256 balanceDiffReward2 = balanceAfterReward2 - balanceBeforeReward2;
        assertEq(balanceDiffReward2, _allocationReward2);
    }

    function testAllocateRewards_ImmediateDistributionShouldBeUpdated() public {
        console.log("ID: R_AR_13");
        console.log("should update immediateDistribution variable when allocateRewards is called");
        uint256 _investableSr = 10000 * Constants.WAD;
        uint256 _investableJr = 100000 * Constants.WAD;

        product.setTokensInvestable(SENIOR_TRANCHE, _investableSr);
        product.setTokensInvestable(JUNIOR_TRANCHE, _investableJr);
        product.setCurrentState(DataTypes.State.INVESTED);

        /// Oracle price set to 20e18 for wAVAX and 1e18 for USDC
        /// Account for junior allocation
        uint256 _allocation = ((jrRewardAPR * _investableJr * DURATION * Constants.WAD) / avaxPrice)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Account for allocation to senior tranche
        _allocation += (srRewardAPR * _investableSr * DURATION) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        deal(address(wavax), rewarder, _allocation);
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), _allocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();

        assertTrue(sut.getAllocationDetails(address(product), address(wavax)).immediateDistribution);

        /// Call allocateRewards again. immediateDistribution should be false

        deal(address(wavax), rewarder, _allocation);
        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), _allocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, false);
        vm.stopPrank();

        assertEq(sut.getAllocationDetails(address(product), address(wavax)).immediateDistribution, false);
    }

    function testAllocateRewards_ShouldTransferWAVAXTwiceWhenCalledTwice() public {
        console.log("ID: R_AR_14");
        console.log("should update rewardSr and rewardJr when allocateRewards is called twice");

        uint256 _investableSr = 10000 * Constants.WAD;
        uint256 _investableJr = 100000 * Constants.WAD;

        product.setTokensInvestable(SENIOR_TRANCHE, _investableSr);
        product.setTokensInvestable(JUNIOR_TRANCHE, _investableJr);
        product.setCurrentState(DataTypes.State.INVESTED);

        /// Account for junior allocation
        uint256 _allocationJr = ((jrRewardAPR * _investableJr * DURATION * Constants.WAD) / avaxPrice)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Account for allocation to senior tranche
        uint256 _allocationSr =
            (srRewardAPR * _investableSr * DURATION) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        uint256 totalAllocation = _allocationJr + _allocationSr;

        deal(address(wavax), rewarder, totalAllocation);

        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), totalAllocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();

        assertEq(sut.getAllocationDetails(address(product), address(wavax)).rewardSr, _allocationSr);

        assertEq(sut.getAllocationDetails(address(product), address(wavax)).rewardJr, _allocationJr);

        // ======== Allocate Rewards Again ========
        deal(address(wavax), rewarder, totalAllocation);

        vm.startPrank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), totalAllocation);
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
        vm.stopPrank();

        assertEq(sut.getAllocationDetails(address(product), address(wavax)).rewardSr, _allocationSr + _allocationSr);

        assertEq(sut.getAllocationDetails(address(product), address(wavax)).rewardJr, _allocationJr + _allocationJr);
    }

    function testAllocateRewards_ShouldEmitEvent() public {
        console.log("ID: R_AR_15");
        console.log("should emit event after allocateRewards is called");

        uint256 _investableSr = 10000 * Constants.WAD;
        uint256 _investableJr = 100000 * Constants.WAD;

        product.setTokensInvestable(SENIOR_TRANCHE, _investableSr);
        product.setTokensInvestable(JUNIOR_TRANCHE, _investableJr);
        product.setCurrentState(DataTypes.State.INVESTED);

        /// Account for junior allocation
        uint256 _allocationJr = ((jrRewardAPR * _investableJr * DURATION * Constants.WAD) / avaxPrice)
            / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        /// Account for allocation to senior tranche
        uint256 _allocationSr =
            (srRewardAPR * _investableSr * DURATION) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);

        uint256 totalAllocation = _allocationJr + _allocationSr;

        deal(address(wavax), rewarder, totalAllocation);

        vm.prank(address(rewarder));
        IERC20Metadata(address(wavax)).approve(address(sut), totalAllocation);

        vm.expectEmit(true, true, true, true);
        emit RewardAllocated(address(product), address(wavax), _allocationSr, _allocationJr, true);
        vm.prank(address(rewarder));
        sut.allocateRewards(IFEYProduct(address(product)), address(wavax), srRewardAPR, jrRewardAPR, true);
    }
}
