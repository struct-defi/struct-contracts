// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "../../common/rewarder/RewarderBaseTestSetup.sol";
import "@core/libraries/helpers/Constants.sol";

contract RewarderClaimRewardsAVAXJunior_UnitTest is RewarderBaseTestSetup {
    uint256 srDeposit = 20 * 1e6;
    uint256 jrDeposit = 1e18;

    /// Default rewards will be wavax. Will reassign when testing for usdc rewards
    uint256 rewardSr = (srRewardAPR * srInvestable * DURATION * usdcPriceWAD)
        / (avaxPrice * Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR);
    uint256 rewardJr = (jrRewardAPR * jrInvestable * DURATION) / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR);

    event RewardClaimed(
        address indexed product,
        address indexed rewardToken,
        address indexed investor,
        uint256 allocationSr,
        uint256 allocationJr
    );

    function onSetup() public virtual override {
        depositInvestTestsFixture(false);
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

    function testClaimRewards_RevertWhenProductNotWithdrawn() public {
        console.log("ID: R_CRAJ_1");
        console.log(
            "should revert when claimRewards is called while immediateDistribution is false and product state is still INVESTED"
        );
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, false);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
    }

    function testClaimRewards_RevertWhenUserHasNoInvestment() public {
        console.log("ID: R_CRAJ_2");
        console.log("should revert when claimRewards is called by a user that has no investment");
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_NOT_ELIGIBLE));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
    }

    function testClaimRewards_RevertWhenUserHasAlreadyClaimedSeniorAndJunior() public {
        console.log("ID: R_CRAJ_3");
        console.log(
            "should revert when claimRewards is called by a user that has already claimed. User deposited in both tranches."
        );
        /// Deposit into senior and junior tranche
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        vm.startPrank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_INSUFFICIENT_ALLOCATION));
        sut.claimRewards(address(product), address(wavax));
        vm.stopPrank();
    }

    function testClaimRewards_RevertWhenUserHasAlreadyClaimedSenior() public {
        console.log("ID: R_CRAJ_4");
        console.log(
            "should revert when claimRewards is called by a user that has already claimed. User deposited in senior tranche"
        );
        /// Only deposit into senior tranche
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        vm.startPrank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_INSUFFICIENT_ALLOCATION));
        sut.claimRewards(address(product), address(wavax));
        vm.stopPrank();
    }

    function testClaimRewards_RevertWhenUserHasAlreadyClaimedJunior() public {
        console.log("ID: R_CRAJ_5");
        console.log(
            "should revert when claimRewards is called by a user that has already claimed. User deposited in junior tranche"
        );
        /// Only deposit into junior tranche
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        vm.startPrank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_INSUFFICIENT_ALLOCATION));
        sut.claimRewards(address(product), address(wavax));
        vm.stopPrank();
    }

    function testClaimRewards_RevertWhenProductHasNoRewards() public {
        console.log("ID: R_CRAJ_6");
        console.log("should revert when claimRewards is called even though product has not been allocated rewards.");
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductDetails();

        /// Reverts when product has not been allocated rewards in INVESTED state
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_NO_ALLOCATION));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));

        /// Reverts when product has not been allocated rewards in WITHDRAWN state
        product.setCurrentState(DataTypes.State.WITHDRAWN);
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_NO_ALLOCATION));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
    }

    function testClaimRewards_ShouldReceiveRewardsForSeniorTranche() public {
        console.log("ID: R_CRAJ_7");
        console.log("investor should receive rewards for investment in senior tranche");

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        uint256 _balanceBefore = wavax.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        uint256 _toReceive = (rewardSr * srDepositWAD) / srInvestable;
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 _received = wavax.balanceOf(address(user1)) - _balanceBefore;
        assertEq(_received, _toReceive);
    }

    function testClaimRewards_ShouldReceiveRewardsForJuniorTranche() public {
        console.log("ID: R_CRAJ_8");
        console.log("investor should receive rewards for investment in junior tranche");

        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        uint256 _balanceBefore = wavax.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        uint256 _toReceive = (rewardJr * jrDeposit) / jrInvestable;
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 _received = wavax.balanceOf(address(user1)) - _balanceBefore;
        assertEq(_received, _toReceive);
    }

    function testClaimRewards_ShouldReceiveRewardsForBothTranche() public {
        console.log("ID: R_CRAJ_9");
        console.log("investor should receive rewards for investment in both senior and junior tranche");

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        uint256 _balanceBefore = wavax.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        uint256 _toReceive = (rewardJr * jrDeposit) / jrInvestable;
        _toReceive += (rewardSr * srDepositWAD) / srInvestable;
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 _received = wavax.balanceOf(address(user1)) - _balanceBefore;
        assertEq(_received, _toReceive);
    }

    function testClaimRewards_ShouldReceiveRewardsWhenProductIsWithdrawn() public {
        console.log("ID: R_CRAJ_10");
        console.log(
            "investor should receive rewards for investment when product is in WITHDRAWN state and immediateDistribution is false"
        );
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, false);
        /// Expect revert when state is INVESTED and immediateDistribution is false
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));

        /// Should pass once product is in WITHDRAWN state
        product.setCurrentState(DataTypes.State.WITHDRAWN);

        uint256 _balanceBefore = wavax.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        uint256 _toReceive = (rewardJr * jrDeposit) / jrInvestable;
        _toReceive += (rewardSr * srDepositWAD) / srInvestable;
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 _received = wavax.balanceOf(address(user1)) - _balanceBefore;
        assertEq(_received, _toReceive);
    }

    function testClaimRewards_ShouldEmitEvent() public {
        console.log("ID: R_CRAJ_11");
        console.log("should emit event after claimRewards is called");
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        /// Calculation of amount of wavax to received by investor
        uint256 _allocationSr = (rewardSr * srDepositWAD) / srInvestable;
        uint256 _allocationJr = (rewardJr * jrDeposit) / jrInvestable;
        vm.expectEmit(true, true, true, true);
        emit RewardClaimed(address(product), address(wavax), address(user1), _allocationSr, _allocationJr);
        vm.recordLogs();
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(
            entries[entries.length - 1].topics[0], keccak256("RewardClaimed(address,address,address,uint256,uint256)")
        );
    }

    function testClaimRewards_ShouldReceiveRewardsWhenRewardsAllocatedTwice() public {
        console.log("ID: R_CRAJ_12");
        console.log(
            "investor should receive rewards for investment when product is allocated rewards twice and they claim in between."
        );
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        uint256 _balanceBefore = wavax.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        uint256 _toReceive = (rewardJr * jrDeposit) / jrInvestable;
        _toReceive += (rewardSr * srDepositWAD) / srInvestable;
        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 _received = wavax.balanceOf(address(user1)) - _balanceBefore;
        assertEq(_received, _toReceive);

        /// Test claimRewards again. Expect revert...
        vm.prank(address(user1));
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_INSUFFICIENT_ALLOCATION));
        sut.claimRewards(address(product), address(wavax));

        /// Run allocateRewards again
        _allocateRewards(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);

        _balanceBefore = wavax.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        _toReceive = (2 * rewardJr * jrDeposit) / jrInvestable;
        _toReceive += (2 * rewardSr * srDepositWAD) / srInvestable;

        /// deduct past amount received
        _toReceive -= _received;

        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        _received = wavax.balanceOf(address(user1)) - _balanceBefore;

        /// User receives rewards again.
        assertEq(_received, _toReceive);
    }

    function testClaimRewards_ShouldSupportRewardsInDifferentDecimals() public {
        console.log("ID: R_CRAJ_13");
        console.log("investor should receive rewards with different decimals");

        rewardSr =
            (srRewardAPR * srInvestable * DURATION) / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR * 1e12);
        rewardJr = (jrRewardAPR * jrInvestable * DURATION * avaxPrice)
            / (usdcPriceWAD * Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR * 1e12);

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);

        _setProductAndAllocate(address(usdc), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);

        uint256 _balanceBefore = usdc.balanceOf(address(user1));
        /// Calculation of amount of wavax to received by investor
        uint256 _toReceive = (rewardJr * jrDeposit) / jrInvestable;
        _toReceive += (rewardSr * srDepositWAD) / srInvestable;

        vm.prank(address(user1));
        sut.claimRewards(address(product), address(usdc));
        uint256 _received = usdc.balanceOf(address(user1)) - _balanceBefore;
        assertEq(_received, _toReceive);
    }

    function testClaimRewards_ShouldSupportMultipleRewardsInDifferentDecimals() public {
        console.log("ID: R_CRAJ_14");
        console.log("investor should receive multiple rewards with different decimals");

        uint256 jrRewardUSDC = (jrRewardAPR * jrInvestable * DURATION * avaxPrice) / usdcPriceWAD
            / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR * 1e12);

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);

        _setProductAndAllocate(address(wavax), srRewardAPR, 0, rewardSr, true);
        _allocateRewards(address(usdc), 0, jrRewardAPR, jrRewardUSDC, true);

        uint256 _balanceBeforeUSDC = usdc.balanceOf(address(user1));
        uint256 _balanceBeforeWAVAX = wavax.balanceOf(address(user1));

        uint256 _toReceiveSr = (rewardSr * srDepositWAD) / srInvestable;
        uint256 _toReceiveJr = (jrRewardUSDC * jrDeposit) / jrInvestable;

        vm.startPrank(address(user1));
        sut.claimRewards(address(product), address(usdc));
        sut.claimRewards(address(product), address(wavax));
        uint256 _receivedUSDC = usdc.balanceOf(address(user1)) - _balanceBeforeUSDC;
        uint256 _receivedWAVAX = wavax.balanceOf(address(user1)) - _balanceBeforeWAVAX;
        assertEq(_receivedUSDC, _toReceiveJr);
        assertEq(_receivedWAVAX, _toReceiveSr);
        vm.stopPrank();
    }

    function testClaimRewards_ShouldReceiveRewardsForMultipleDeposits() public {
        console.log("ID: R_CRAS_15");
        console.log(
            "multiple investor should receive rewards for investment in both senior and junior tranche for multiple deposits"
        );

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(admin, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(admin, srDeposit, SENIOR_TRANCHE);

        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _deposit(admin, jrDeposit, JUNIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);
        _deposit(admin, jrDeposit, JUNIOR_TRANCHE);

        _setProductAndAllocate(address(wavax), srRewardAPR, jrRewardAPR, rewardSr + rewardJr, true);
        uint256 _balanceBeforeUser1 = wavax.balanceOf(address(user1));
        uint256 _balanceBeforeUser2 = wavax.balanceOf(address(admin));

        uint256 _toReceive = (2 * rewardJr * jrDeposit) / jrInvestable + (2 * rewardSr * srDepositWAD) / srInvestable;

        vm.prank(address(user1));
        sut.claimRewards(address(product), address(wavax));
        uint256 _receivedUser1 = wavax.balanceOf(address(user1)) - _balanceBeforeUser1;
        assertEq(_receivedUser1, _toReceive);

        vm.prank(address(admin));
        sut.claimRewards(address(product), address(wavax));
        uint256 _receivedUser2 = wavax.balanceOf(address(admin)) - _balanceBeforeUser2;
        assertEq(_receivedUser2, _toReceive);
    }

    function testClaimRewards_TransferSpToken() public {
        console.log("ID: R_CRAS_16");
        console.log(
            "user can still claim rewards after they transfer all SP tokens to another user, and the other user cannot claim rewards"
        );

        uint256 jrRewardUSDC = (jrRewardAPR * jrInvestable * DURATION * avaxPrice) / usdcPriceWAD
            / (Constants.YEAR_IN_SECONDS * Constants.DECIMAL_FACTOR * 1e12);

        _deposit(user1, srDeposit, SENIOR_TRANCHE);
        _deposit(user1, jrDeposit, JUNIOR_TRANCHE);

        uint256 _spTokensToTransferSr = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));
        uint256 _spTokensToTransferJr = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));
        handleTransferSpToken(_spTokensToTransferSr, address(user1), address(user2), SENIOR_TRANCHE);
        handleTransferSpToken(_spTokensToTransferJr, address(user1), address(user2), JUNIOR_TRANCHE);

        assertEq(spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE)), 0, "user1 senior SP token balance is 0");
        assertEq(
            spToken.balanceOf(address(user2), uint256(SENIOR_TRANCHE)),
            _spTokensToTransferSr,
            "user2 senior SP token balance is user1's previous balance"
        );
        assertEq(spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE)), 0, "user1 junior SP token balance is 0");
        assertEq(
            spToken.balanceOf(address(user2), uint256(JUNIOR_TRANCHE)),
            _spTokensToTransferJr,
            "user2 junior SP token balance is user1's previous balance"
        );

        _setProductAndAllocate(address(wavax), srRewardAPR, 0, rewardSr, true);
        _allocateRewards(address(usdc), 0, jrRewardAPR, jrRewardUSDC, true);

        uint256 _balanceBeforeUSDC = usdc.balanceOf(address(user1));
        uint256 _balanceBeforeWAVAX = wavax.balanceOf(address(user1));

        uint256 _toReceiveSr = (rewardSr * srDepositWAD) / srInvestable;
        uint256 _toReceiveJr = (jrRewardUSDC * jrDeposit) / jrInvestable;

        vm.startPrank(address(user1));
        sut.claimRewards(address(product), address(usdc));
        sut.claimRewards(address(product), address(wavax));
        vm.stopPrank();
        uint256 _receivedUSDC = usdc.balanceOf(address(user1)) - _balanceBeforeUSDC;
        uint256 _receivedWAVAX = wavax.balanceOf(address(user1)) - _balanceBeforeWAVAX;
        assertEq(_receivedUSDC, _toReceiveJr, "user1 received correct amount of USDC rewards");
        assertEq(_receivedWAVAX, _toReceiveSr, "user1 received correct amount of wAVAX rewards");

        vm.startPrank(address(user2));
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_NOT_ELIGIBLE));
        sut.claimRewards(address(product), address(usdc));
        vm.expectRevert(abi.encodePacked(Errors.VE_REWARDER_NOT_ELIGIBLE));
        sut.claimRewards(address(product), address(wavax));
        vm.stopPrank();
    }
}
