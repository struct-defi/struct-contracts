pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";
import "@mocks/MockERC20.sol";

import "../../../common/fey-products/gmx/FEYProductBaseTestSetup.sol";

contract FGMXPDepositFor_UnitTest is FEYProductBaseTestSetup {
    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testDepositFor_RevertInsufficientAllowance() public {
        console.log("should revert when there is insufficient allowance for deposit");

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed"));
        user1.depositToSeniorFor(1e18, address(user1));
    }

    function testDepositFor_RevertACL() public {
        console.log("should revert when called by non-factory role account");

        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user3.depositToSeniorFor(1e18, address(user1));

        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user3.depositToJuniorFor(1e18, address(user1));
    }

    function testDepositFor_RevertInsufficientBalance() public {
        console.log("should revert when there is insufficient tokens to deposit in the wallet");

        user1.increaseAllowance(address(wavax), 1e18);
        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed"));
        user1.depositToSeniorFor(1e18, address(user1));
    }

    function testDepositFor_RevertWhenLocalPaused() public {
        console.log("ID: Pr_DepFr_1");
        console.log("should revert when the contract is paused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToJuniorFor(10, address(user2));

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToSeniorFor(10, address(user2));
    }

    function testDepositFor_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_DepFr_2");

        console.log("should revert when the contract is paused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToJuniorFor(10, address(user2));

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToSeniorFor(10, address(user2));
    }

    function testDepositFor_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_DepFr_3");

        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToJuniorFor(10, address(user2));

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositToSeniorFor(10, address(user2));

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked("ERC20: insufficient allowance"));
        user1.depositToJuniorFor(10, address(user2));

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed")); // wavax uses different interface
        user1.depositToSeniorFor(10, address(user2));
    }

    function testDepositFor_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_DepFr_4");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToJuniorFor(10, address(user2));

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositToSeniorFor(10, address(user2));

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked("ERC20: insufficient allowance"));
        user1.depositToJuniorFor(10, address(user2));

        vm.expectRevert(abi.encodePacked("SafeERC20: low-level call failed")); // wavax uses different interface
        user1.depositToSeniorFor(10, address(user2));
    }

    function testDepositFor_RevertDepositAmountExceedsCapacity() public {
        console.log("should revert if the deposit amount exceeds tranche max capacity");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 100000000e18);
        user1.increaseAllowance(address(wavax), 100000000e18);

        vm.expectRevert(abi.encodePacked(Errors.VE_AMOUNT_EXCEEDS_CAP));
        user1.depositToSeniorFor(100000000e18, address(user1));

        usdc.mint(address(user1), 100000000e6);
        user1.increaseAllowance(address(usdc), 100000000e6);

        /// Should not revert as it is within cap
        user1.depositToJuniorFor(5000e6, address(user1));

        vm.expectRevert(abi.encodePacked(Errors.VE_AMOUNT_EXCEEDS_CAP));
        user1.depositToJuniorFor(15001e6, address(user1));
    }

    function testDepositFor_RevertDepositsClosed() public {
        console.log("should revert when tried to deposit after the deposits are closed");

        vm.warp(block.timestamp + 10 weeks);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 1e18);
        user1.increaseAllowance(address(wavax), 1e18);

        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSITS_CLOSED));
        user1.depositToSeniorFor(1e18, address(user1));

        usdc.mint(address(user1), 10e6);
        user1.increaseAllowance(address(usdc), 10e6);

        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSITS_CLOSED));
        user1.depositToJuniorFor(10e6, address(user1));
    }

    function testDepositFor_SeniorUserInvestmentWithinCapacity() public {
        console.log("senior tranche user investment amount should be sum of user deposits and excess should be zero");

        /// Initial balance of the product contract should be zero
        assertEq(wavax.balanceOf(address(sut)), 0);

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 10e18);
        user1.increaseAllowance(address(wavax), 2e18);

        user1.depositToSeniorFor(1e18, address(user2));

        (, uint256 excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user2));
        uint256 _userTotalDepositedSr = sut.getUserTotalDeposited(SENIOR_TRANCHE, address(user2));
        assertEq(_userTotalDepositedSr, 1e18);

        user1.depositToSeniorFor(1e18, address(user2));

        (, excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user2));
        _userTotalDepositedSr = sut.getUserTotalDeposited(SENIOR_TRANCHE, address(user2));
        assertEq(_userTotalDepositedSr, 2e18);
        assertEq(_userTotalDepositedSr, wavax.balanceOf(address(sut)));

        assertEq(excess, 0);
    }

    function testDepositFor_JuniorUserInvestmentWithinCapacity() public {
        console.log("junior tranche user investment amount should be sum of user deposits and excess should be zero");

        /// Initial balance of the product contract should be zero
        assertEq(usdc.balanceOf(address(sut)), 0);

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        usdc.mint(address(user1), 10e6);
        user1.increaseAllowance(address(usdc), 2e6);

        user1.depositToJuniorFor(1e6, address(user2));

        (, uint256 excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user2));
        uint256 _userTotalDepositedJr = sut.getUserTotalDeposited(JUNIOR_TRANCHE, address(user2));
        assertEq(_userTotalDepositedJr, 1e18);

        user1.depositToJuniorFor(1e6, address(user2));

        (, excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user2));
        _userTotalDepositedJr = sut.getUserTotalDeposited(JUNIOR_TRANCHE, address(user2));
        assertEq(_userTotalDepositedJr, 2e18);
        assertEq(_userTotalDepositedJr, usdc.balanceOf(address(sut)) * 10 ** 12);

        assertEq(excess, 0);
    }

    function testDepositFor_ShouldMintSPTokens() public {
        console.log("should mint StructSPTokens to the recipient (behalf of) address after deposit");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 10e18);
        user1.increaseAllowance(address(wavax), 2e18);

        user1.depositToSeniorFor(1e18, address(user2));
        uint256 seniorTrancheSPTokenBalanceOfDepositor = spToken.balanceOf(address(user1), 0);
        uint256 seniorTrancheSPTokenBalanceOfRecipient = spToken.balanceOf(address(user2), 0);

        assertEq(seniorTrancheSPTokenBalanceOfDepositor, 0);
        assertEq(seniorTrancheSPTokenBalanceOfRecipient, 1e18);

        user1.depositToSeniorFor(1e18, address(user2));

        seniorTrancheSPTokenBalanceOfRecipient = spToken.balanceOf(address(user2), 0);

        assertEq(seniorTrancheSPTokenBalanceOfDepositor, 0);
        assertEq(seniorTrancheSPTokenBalanceOfRecipient, 2e18);

        /// Junior tranche

        usdc.mint(address(user1), 10e6);
        user1.increaseAllowance(address(usdc), 2e6);

        user1.depositToJuniorFor(1e6, address(user2));

        uint256 juniorTrancheSPTokenBalanceOfDepositor = spToken.balanceOf(address(user1), 1);
        uint256 juniorTrancheSPTokenBalanceOfRecipient = spToken.balanceOf(address(user2), 1);

        assertEq(juniorTrancheSPTokenBalanceOfDepositor, 0);
        assertEq(juniorTrancheSPTokenBalanceOfRecipient, 1e18);

        user1.depositToJuniorFor(1e6, address(user2));

        juniorTrancheSPTokenBalanceOfDepositor = spToken.balanceOf(address(user1), 1);
        juniorTrancheSPTokenBalanceOfRecipient = spToken.balanceOf(address(user2), 1);

        assertEq(juniorTrancheSPTokenBalanceOfDepositor, 0);
        assertEq(juniorTrancheSPTokenBalanceOfRecipient, 2e18);
    }

    function testDepositFor_SeniorTranche_UserSumsDepositSums_SingleUser() public {
        console.log("should update user sums and deposit sums for single user - senior tranche");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 10e18);
        user1.increaseAllowance(address(wavax), 2e18);

        user1.depositToSeniorFor(1e18, address(user1));

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 1);
        assertEq(investor1.depositSums.length, 1);

        assertEq(investor1.userSums[0], 1e18);
        assertEq(investor1.depositSums[0], 1e18);

        user1.depositToSeniorFor(1e18, address(user1));

        investor1 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 2);
        assertEq(investor1.depositSums.length, 2);

        assertEq(investor1.userSums[1], 2e18);
        assertEq(investor1.depositSums[1], 2e18);
    }

    function testDepositFor_SeniorTranche_UserSumsDepositSums_MultipleUsers() public {
        console.log("should update user sums and deposit sums for multiple users - senior tranche");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), 10e18);
        user1.increaseAllowance(address(wavax), 2e18);

        user1.depositToSeniorFor(1e18, address(user1));

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        deal(address(wavax), address(user2), 10e18);
        user2.increaseAllowance(address(wavax), 10e18);

        user2.depositToSeniorFor(5e18, address(user2));
        user2.depositToSeniorFor(3e18, address(user2));

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

    function testDepositFor_JuniorTranche_UserSumsDepositSums_SingleUser() public {
        console.log("should update user sums and deposit sums for single user - junior tranche");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        usdc.mint(address(user1), 2e6);
        user1.increaseAllowance(address(usdc), 2e6);

        user1.depositToJuniorFor(1e6, address(user1));

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 1);
        assertEq(investor1.depositSums.length, 1);

        assertEq(investor1.userSums[0], 1e18);
        assertEq(investor1.depositSums[0], 1e18);

        user1.depositToJuniorFor(1e6, address(user1));

        investor1 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        assertEq(investor1.userSums.length, 2);
        assertEq(investor1.depositSums.length, 2);

        assertEq(investor1.userSums[1], 2e18);
        assertEq(investor1.depositSums[1], 2e18);
    }

    function testDepositFor_JuniorTranche_UserSumsDepositSums_MultipleUsers() public {
        console.log("should update user sums and deposit sums");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        usdc.mint(address(user1), 10e6);
        user1.increaseAllowance(address(usdc), 10e6);

        user1.depositToJuniorFor(1e6, address(user1));

        DataTypes.Investor memory investor1 = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        usdc.mint(address(user2), 10e6);
        user2.increaseAllowance(address(usdc), 10e6);

        user2.depositToJuniorFor(5e6, address(user2));
        user2.depositToJuniorFor(3e6, address(user2));

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
}
