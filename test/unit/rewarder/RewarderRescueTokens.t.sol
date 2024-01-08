// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "../../common/rewarder/RewarderBaseTestSetup.sol";
import "@core/libraries/helpers/Constants.sol";

contract RewarderRescueTokens_UnitTest is RewarderBaseTestSetup {
    uint256 srDeposit = 1e18;
    uint256 jrDeposit = 20 * 1e6;
    /// Default rewards will be wavax. Will reassign when testing for usdc rewards
    uint256 rewardSr = (srRewardAPR * srInvestable * DURATION) / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR);
    uint256 rewardJr = (jrRewardAPR * jrInvestable * DURATION * usdcPriceWAD)
        / (avaxPrice * Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR);

    uint256 rewardTotal = rewardSr + rewardJr;

    event TokensRescued(address indexed product, address indexed rewardToken, uint256 amount);

    function onSetup() public virtual override {
        depositInvestTestsFixture(true);
    }

    function _setProductAndAllocate(
        address _rewardToken,
        uint256 _srRewardAPR,
        uint256 _jrRewardAPR,
        uint256 _rewardAllocation,
        bool _immediateDistribution
    ) internal {
        _setProductDetails();
        _allocateRewards(_rewardToken, _srRewardAPR, _jrRewardAPR, _rewardAllocation, _immediateDistribution);
    }

    function _setProductDetails() internal {
        product.setTokensInvestable(SENIOR_TRANCHE, srInvestable);
        product.setTokensInvestable(JUNIOR_TRANCHE, jrInvestable);
        product.setCurrentState(DataTypes.State.INVESTED);
    }

    function _allocateRewards(
        address _rewardToken,
        uint256 _srRewardAPR,
        uint256 _jrRewardAPR,
        uint256 _rewardAllocation,
        bool _immediateDistribution
    ) internal {
        deal(_rewardToken, address(rewarder), _rewardAllocation);
        vm.startPrank(address(rewarder));
        IERC20Metadata(_rewardToken).approve(address(sut), _rewardAllocation);
        sut.allocateRewards(
            IFEYProduct(address(product)), _rewardToken, _srRewardAPR, _jrRewardAPR, _immediateDistribution
        );
        vm.stopPrank();
    }

    function testRescueTokens_RevertWhenNoRewarderRole() public {
        console.log("ID: R_RT_1");
        console.log("should revert when no rewarder role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        vm.prank(address(user1));
        sut.rescueTokens(address(product), address(wavax));
    }

    function testRescueTokens_RevertWhenNoRewardsAllocated() public {
        console.log("ID: R_RT_2");
        console.log("should revert when no rewards allocated");
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_NO_ALLOCATION));
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));
    }

    function testRescueTokens_RewarderShouldReceiveRewardTokens() public {
        console.log("ID: R_RT_3");
        console.log("Rewarder should receive rewards allocated");
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardTotal, true);
        uint256 rewarderBalanceBefore = wavax.balanceOf(address(rewarder));
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));
        uint256 rewarderBalanceChange = wavax.balanceOf(address(rewarder)) - rewarderBalanceBefore;
        assertEq(rewarderBalanceChange, rewardTotal);
    }

    function testRescueTokens_RewarderShouldReceiveRewardTokensEvenIfImmediateDistributionIsFalse() public {
        console.log("ID: R_RT_4");
        console.log("Rewarder should receive rewards allocated even if immediateDistribution is false");
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardTotal, false);
        uint256 rewarderBalanceBefore = wavax.balanceOf(address(rewarder));
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));
        uint256 rewarderBalanceChange = wavax.balanceOf(address(rewarder)) - rewarderBalanceBefore;
        assertEq(rewarderBalanceChange, rewardTotal);
    }

    function testRescueTokens_RewarderShouldReceiveRewardTokensInWithdrawnState() public {
        console.log("ID: R_RT_5");
        console.log("Rewarder should receive rewards allocated in WITHDRAWN state");
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardTotal, true);
        product.setCurrentState(DataTypes.State.WITHDRAWN);
        uint256 rewarderBalanceBefore = wavax.balanceOf(address(rewarder));
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));
        uint256 rewarderBalanceChange = wavax.balanceOf(address(rewarder)) - rewarderBalanceBefore;
        assertEq(rewarderBalanceChange, rewardTotal);
    }

    function testRescueTokens_RewarderShouldReceiveRewardTokensMinusClaimedAmount() public {
        console.log("ID: R_RT_6");
        console.log("Rewarder should receive rewards allocated");
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user2, srDeposit, SENIOR_TRANCHE);
        _deposit(admin, srDeposit, SENIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardTotal, true);

        /// User1 claims rewards
        uint256 balanceBeforeUser1 = wavax.balanceOf(address(user1));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 receivedUser1 = wavax.balanceOf(address(user1)) - balanceBeforeUser1;

        /// User2 claims rewards
        uint256 balanceBeforeUser2 = wavax.balanceOf(address(user2));
        vm.prank(address(user2));
        sut.claimRewards(address(product), address(wavax));
        uint256 receivedUser2 = wavax.balanceOf(address(user2)) - balanceBeforeUser2;

        /// Rewarder should receive rewards allocated minus claimed amount
        uint256 rewarderBalanceBefore = wavax.balanceOf(address(rewarder));
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));
        uint256 rewarderBalanceChange = wavax.balanceOf(address(rewarder)) - rewarderBalanceBefore;
        assertEq(rewarderBalanceChange, rewardTotal - receivedUser1 - receivedUser2);
    }

    function testRescueTokens_RewarderShouldReceiveDifferentRewardTokens() public {
        console.log("ID: R_RT_7");
        console.log("Rewarder should receive different reward tokens");

        rewardSr = (srRewardAPR * srInvestable * DURATION * avaxPrice) / usdcPriceWAD
            / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR * 1e12);
        rewardJr =
            (jrRewardAPR * jrInvestable * DURATION) / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR * 1e12);

        rewardTotal = rewardSr + rewardJr;

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user2, srDeposit, SENIOR_TRANCHE);
        _deposit(admin, srDeposit, SENIOR_TRANCHE);
        _setProductAndAllocate(address(usdc), srRewardAPR, jrRewardAPR, rewardTotal, true);

        /// User1 claims rewards
        uint256 balanceBeforeUser1 = usdc.balanceOf(address(user1));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(usdc));
        uint256 receivedUser1 = usdc.balanceOf(address(user1)) - balanceBeforeUser1;

        /// User2 claims rewards
        uint256 balanceBeforeUser2 = usdc.balanceOf(address(user2));
        vm.prank(address(user2));
        sut.claimRewards(address(product), address(usdc));
        uint256 receivedUser2 = usdc.balanceOf(address(user2)) - balanceBeforeUser2;

        /// Rewarder should receive rewards allocated minus claimed amount
        uint256 rewarderBalanceBefore = usdc.balanceOf(address(rewarder));
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(usdc));
        uint256 rewarderBalanceChange = usdc.balanceOf(address(rewarder)) - rewarderBalanceBefore;
        assertEq(rewarderBalanceChange, rewardTotal - receivedUser1 - receivedUser2);
    }

    function testRescueTokens_ShouldEmitEvent() public {
        console.log("ID: R_RT_8");
        console.log("should emit event after rescueTokens is called");
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardTotal, true);

        vm.expectEmit(true, true, true, true);
        emit TokensRescued(address(product), address(wavax), rewardTotal);
        vm.recordLogs();
        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries[entries.length - 1].topics[0], keccak256("TokensRescued(address,address,uint256)"));
    }

    function testRescueTokens_ShouldRefreshAllocationDetails() public {
        console.log("ID: R_RT_9");
        console.log("allocationDetails should be deleted after rescueTokens is called");
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardTotal, true);

        vm.prank(address(rewarder));
        sut.rescueTokens(address(product), address(wavax));

        RewarderHarness.AllocationDetails memory _allocationDetails =
            sut.getAllocationDetails(address(product), address(wavax));

        assertEq(_allocationDetails.rewardSr, 0);
        assertEq(_allocationDetails.rewardJr, 0);
        assertEq(_allocationDetails.claimedSr, 0);
        assertEq(_allocationDetails.claimedJr, 0);
        assertEq(_allocationDetails.immediateDistribution, false);
    }

    /// TODO Test rescue tokens after multiple products have been allocated to
    /// We make sure that we only rescue tokens for a particular product
}
