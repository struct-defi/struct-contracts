pragma solidity 0.8.11;

import "@interfaces/IFEYFactory.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-products/autopool/FEYProductBaseTestSetup.sol";

contract FEYAutoPoolProductDeposit_UnitTest is FEYProductBaseTestSetup {
    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testDepositAP_RevertInsufficientAllowance() public {
        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed"));
        user1.depositToSenior(1e18);
    }

    function testDepositAP_RevertInsufficientBalance() public {
        user1.increaseAllowance(address(wavax), 1e18);
        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed"));
        user1.depositToSenior(1e18);
    }

    function testDepositAP_RevertWhenLocalPaused() public {
        console.log("ID: Pr_Dep_14");
        console.log("should revert when the contract is paused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToJunior(10);

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToSenior(10);
    }

    function testDepositAP_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_Dep_15");

        console.log("should revert when the contract is paused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToJunior(10);

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToSenior(10);
    }

    function testDepositAP_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_Dep_16");

        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToJunior(10);

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToSenior(10);

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked("ERC20: insufficient allowance"));
        user1.depositToJunior(10);

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed")); // wavax uses different interface
        user1.depositToSenior(10);
    }

    function testDepositAP_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_Dep_17");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToJunior(10);

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToSenior(10);

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked("ERC20: insufficient allowance"));
        user1.depositToJunior(10);

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed")); // wavax uses different interface
        user1.depositToSenior(10);
    }

    function testDepositAP_RevertDepositZeroAmount() public {
        console.log("should revert if the deposit amount equals 0");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_DEPOSIT_AMOUNT));
        user1.depositToSenior(0);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_DEPOSIT_AMOUNT));
        user1.depositToJunior(0);
    }

    function testDepositAP_RevertDepositAmountExceedsCapacity() public {
        console.log("should revert if the deposit amount exceeds tranche max capacity");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 100000000e18);
        user1.increaseAllowance(address(wavax), 100000000e18);

        vm.expectRevert(abi.encodePacked(Errors.VE_AMOUNT_EXCEEDS_CAP));
        user1.depositToSenior(100000000e18);

        usdc.mint(address(user1), 100000000e6);
        user1.increaseAllowance(address(usdc), 100000000e6);

        /// Should not revert as it is within cap
        user1.depositToJunior(5000e6);

        vm.expectRevert(abi.encodePacked(Errors.VE_AMOUNT_EXCEEDS_CAP));
        user1.depositToJunior(15001e6);
    }

    function testDepositAP_RevertDepositsClosed() public {
        console.log("should revert if the deposits are closed");

        vm.warp(block.timestamp + 10 weeks);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 1e18);
        user1.increaseAllowance(address(wavax), 1e18);

        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSITS_CLOSED));
        user1.depositToSenior(1e18);

        usdc.mint(address(user1), 10e6);
        user1.increaseAllowance(address(usdc), 10e6);

        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSITS_CLOSED));
        user1.depositToJunior(10e6);
    }

    function testDepositAP_SeniorUserInvestmentExcess() public {
        console.log("senior tranche user investment amount should be sum of user deposits and excess should be zero");

        /// Initial balance of the product contract should be zero
        assertEq(wavax.balanceOf(address(sut)), 0);

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        (, uint256 excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user1));
        uint256 _userTotalDepositedSr = sut.getUserTotalDeposited(SENIOR_TRANCHE, address(user1));
        assertEq(_userTotalDepositedSr, 1e18, "_userTotalDepositedSr #1");

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        (, excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user1));
        _userTotalDepositedSr = sut.getUserTotalDeposited(SENIOR_TRANCHE, address(user1));
        assertEq(_userTotalDepositedSr, 2e18, "_userTotalDepositedSr #2");
        assertEq(
            _userTotalDepositedSr, wavax.balanceOf(address(sut)), "_userTotalDepositedSr is contract wAVAX balance"
        );

        assertEq(excess, 0, "user excess is zero");
    }

    function testDepositAP_JuniorUserInvestmentExcess() public {
        console.log("junior tranche user investment amount should be sum of user deposits and excess should be zero");

        /// Initial balance of the product contract should be zero
        assertEq(usdc.balanceOf(address(sut)), 0);

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        (, uint256 excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user1));
        uint256 _userTotalDepositedJr = sut.getUserTotalDeposited(JUNIOR_TRANCHE, address(user1));
        assertEq(_userTotalDepositedJr, 1e18, "_userTotalDepositedJr #1");

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        (, excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user1));
        _userTotalDepositedJr = sut.getUserTotalDeposited(JUNIOR_TRANCHE, address(user1));
        assertEq(_userTotalDepositedJr, 2e18, "_userTotalDepositedJr #2");
        assertEq(
            _userTotalDepositedJr,
            usdc.balanceOf(address(sut)) * 10 ** 12,
            "_userTotalDepositedJr is contract USDC balance"
        );

        assertEq(excess, 0, "user excess is zero");
    }

    function testDepositAP_ShouldMintSPTokens() public {
        console.log("should mint StructSPTokens to the users after deposit");

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        uint256 seniorTrancheSPTokenBalance = spToken.balanceOf(address(user1), 0);
        assertEq(seniorTrancheSPTokenBalance, 1e18);

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        seniorTrancheSPTokenBalance = spToken.balanceOf(address(user1), 0);
        assertEq(seniorTrancheSPTokenBalance, 2e18);

        /// Junior tranche

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        uint256 juniorTrancheSPTokenBalance = spToken.balanceOf(address(user1), 1);
        assertEq(juniorTrancheSPTokenBalance, 1e18);

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        juniorTrancheSPTokenBalance = spToken.balanceOf(address(user1), 1);
        assertEq(juniorTrancheSPTokenBalance, 2e18);
    }

    function testDepositAP_SeniorTranche_UserSumsDepositSums_SingleUser() public {
        console.log("should track user sums and deposit sums for single user - senior tranche");

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 1);
        assertEq(investor1.depositSums.length, 1);

        assertEq(investor1.userSums[0], 1e18);
        assertEq(investor1.depositSums[0], 1e18);

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        investor1 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 2);
        assertEq(investor1.depositSums.length, 2);

        assertEq(investor1.userSums[1], 2e18);
        assertEq(investor1.depositSums[1], 2e18);
    }

    function testDepositAP_SeniorTranche_UserSumsDepositSums_MultipleUsers() public {
        console.log("should track user sums and deposit sums for multiple users - senior tranche");

        _deposit(user1, 1e18, SENIOR_TRANCHE);

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        _deposit(user2, 5e18, SENIOR_TRANCHE);
        _deposit(user2, 3e18, SENIOR_TRANCHE);

        DataTypes.Investor memory investor2 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user2));

        /// Investor 1 and 2 deposit sums and user sums array length should be equal to number of their deposits.

        assertEq(investor1.userSums.length, 1);
        assertEq(investor1.depositSums.length, 1);

        assertEq(investor2.userSums.length, 2);
        assertEq(investor2.depositSums.length, 2);

        assertEq(investor1.userSums[0], 1e18);
        assertEq(investor1.depositSums[0], 1e18);

        assertEq(investor2.userSums[0], 5e18);
        assertEq(investor2.depositSums[0], 6e18);

        assertEq(investor2.userSums[1], 8e18);
        assertEq(investor2.depositSums[1], 9e18);
    }

    function testDepositAP_JuniorTranche_UserSumsDepositSums_SingleUser() public {
        console.log("should track user sums and deposit sums for single user - junior tranche");

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 1);
        assertEq(investor1.depositSums.length, 1);

        assertEq(investor1.userSums[0], 1e18);
        assertEq(investor1.depositSums[0], 1e18);

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        investor1 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 2);
        assertEq(investor1.depositSums.length, 2);

        assertEq(investor1.userSums[1], 2e18);
        assertEq(investor1.depositSums[1], 2e18);
    }

    function testDepositAP_JuniorTranche_UserSumsDepositSums_MultipleUsers() public {
        console.log("should track user sums and deposit sums for multiple users - junior tranche");

        _deposit(user1, 1e6, JUNIOR_TRANCHE);

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        _deposit(user2, 5e6, JUNIOR_TRANCHE);
        _deposit(user2, 3e6, JUNIOR_TRANCHE);

        DataTypes.Investor memory investor2 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user2));

        /// Investor 1 and 2 deposit sums and user sums array length should be equal to number of their deposits.
        assertEq(investor1.userSums.length, 1);
        assertEq(investor1.depositSums.length, 1);

        assertEq(investor2.userSums.length, 2);
        assertEq(investor2.depositSums.length, 2);

        assertEq(investor1.userSums[0], 1e18);
        assertEq(investor1.depositSums[0], 1e18);

        assertEq(investor2.userSums[0], 5e18);
        assertEq(investor2.depositSums[0], 6e18);

        assertEq(investor2.userSums[1], 8e18);
        assertEq(investor2.depositSums[1], 9e18);
    }

    function testDepositAP_JuniorTranche_RevertInvariantCheckFailed() public {
        console.log("Pr_Dep_28");
        console.log(
            "should revert with error VE_DEPOSIT_INVARIANT_CHECK if tranche tokens owned by product < SP token total supply - junior tranche"
        );
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        uint256 _amountToDeposit = 1e6;
        deal(address(usdc), address(user1), _amountToDeposit);
        user1.increaseAllowance(address(usdc), _amountToDeposit);

        vm.mockCall(address(usdc), abi.encodeWithSelector(usdc.balanceOf.selector), abi.encode(0));
        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSIT_INVARIANT_CHECK));
        vm.prank(address(user1));
        sut.depositHarness(JUNIOR_TRANCHE, _amountToDeposit);
    }

    function testDepositAP_SeniorTranche_RevertInvariantCheckFailed() public {
        console.log("Pr_Dep_28");
        console.log(
            "should revert with error VE_DEPOSIT_INVARIANT_CHECK if tranche tokens owned by product < SP token total supply - senior tranche"
        );
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        uint256 _amountToDeposit = 1e18;
        deal(address(wavax), address(user1), _amountToDeposit);
        user1.increaseAllowance(address(wavax), _amountToDeposit);

        vm.mockCall(address(wavax), abi.encodeWithSelector(wavax.balanceOf.selector), abi.encode(0));
        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSIT_INVARIANT_CHECK));
        vm.prank(address(user1));
        sut.depositHarness(SENIOR_TRANCHE, _amountToDeposit);
    }

    function testDepositAP_SeniorTranche_PassInvariantCheck() public {
        console.log("Pr_Dep_29");
        console.log(
            "should NOT revert with error VE_DEPOSIT_INVARIANT_CHECK if tokens owned by product > SP tokens - senior tranche"
        );
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        uint256 _amountToDeposit = 1e18;
        deal(address(wavax), address(user1), _amountToDeposit * 2);
        // transfer wAVAX to product without making a deposit
        vm.prank(address(user1));
        wavax.transfer(address(sut), _amountToDeposit);
        user1.increaseAllowance(address(wavax), _amountToDeposit);

        vm.prank(address(user1));
        sut.depositHarness(SENIOR_TRANCHE, _amountToDeposit);
        assertGt(wavax.balanceOf(address(sut)), _amountToDeposit);
    }
}
