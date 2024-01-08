pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-products/autopool/FEYProductBaseTestSetup.sol";

contract FEYAutoPoolProductClaimExcess_UnitTest is FEYProductBaseTestSetup {
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    event ExcessClaimed(
        DataTypes.Tranche _tranche,
        uint256 _spTokenId,
        uint256 _userInvested,
        uint256 _excessAmount,
        address indexed _user
    );

    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testClaimExcess_RevertIfInvalidState() public {
        console.log("should revert when tried to claim excess when the tranche is not yet invested");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_RevertIfNoDeposits() public {
        vm.warp(block.timestamp + 15 minutes);
        console.log("should revert when there is no excess to claim");
        user1.invest();

        vm.expectRevert(abi.encodePacked(Errors.VE_NO_EXCESS));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_NO_EXCESS));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_RevertIfNotAuthorized() public {
        console.log("should revert if the user didn't approve the product contract before claim excess");

        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        vm.expectRevert(abi.encodePacked("NOT_AUTHORIZED"));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_RevertWhenLocalPaused() public {
        console.log("ID: Pr_CE_18");
        console.log("should revert when the contract is paused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_CE_19");

        console.log("should revert when the contract is paused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_CE_20");
        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.claimExcess(JUNIOR_TRANCHE);

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_CE_21");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.claimExcess(JUNIOR_TRANCHE);

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_ShouldClaimJuniorTrancheTokens() public {
        console.log("should update tokensExcess when there are no deposits in the senior tranche");

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        DataTypes.TrancheInfo memory juniorTrancheInfoBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        user1.claimExcess(JUNIOR_TRANCHE);

        DataTypes.TrancheInfo memory juniorTrancheInfoAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(juniorTrancheInfoBefore.tokensExcess, usdcToDeposit * 10 ** 12);
        assertEq(juniorTrancheInfoAfter.tokensExcess, 0);
    }

    function testClaimExcess_ShouldClaimSeniorTrancheTokens() public {
        console.log("should update tokensExcess when there are no deposits in the junior tranche");

        _depositWarpInvestAndSetApproval(user1, wavaxToDeposit, SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory seniorTrancheInfoBefore = sut.getTrancheInfo(SENIOR_TRANCHE);

        user1.claimExcess(SENIOR_TRANCHE);

        DataTypes.TrancheInfo memory seniorTrancheInfoAfter = sut.getTrancheInfo(SENIOR_TRANCHE);

        assertEq(seniorTrancheInfoBefore.tokensExcess, wavaxToDeposit);
        assertEq(seniorTrancheInfoAfter.tokensExcess, 0);
    }

    function testClaimExcess_ShouldBurnJuniorTrancheSPTokens() public {
        console.log(
            "should burn all the SPToken share of junior tranche when there are no deposits in the senior tranche"
        );

        _depositWarpInvestAndSetApproval(user1, wavaxToDeposit, SENIOR_TRANCHE);

        uint256 spTokenBalanceBefore = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));

        user1.claimExcess(SENIOR_TRANCHE);

        uint256 spTokenBalanceAfter = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));

        assertEq(spTokenBalanceBefore, wavaxToDeposit);
        assertEq(spTokenBalanceAfter, 0);
    }

    function testClaimExcess_ShouldBurnSeniorTrancheSPTokens() public {
        console.log(
            "should burn all the SPToken share of junior tranche when there are no deposits in the senior tranche"
        );

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        uint256 spTokenBalanceBefore = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));

        user1.claimExcess(JUNIOR_TRANCHE);

        uint256 spTokenBalanceAfter = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));

        assertEq(spTokenBalanceBefore, usdcToDeposit * 10 ** 12);
        assertEq(spTokenBalanceAfter, 0);
    }

    function testClaimExcess_ShouldTransferSeniorTrancheTokens() public {
        console.log("should transfer the excess senior tranche tokens to the user");

        _depositWarpInvestAndSetApproval(user1, wavaxToDeposit, SENIOR_TRANCHE);

        uint256 productTrancheTokensBalanceBefore = wavax.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceBefore = wavax.balanceOf(address(user1));

        user1.claimExcess(SENIOR_TRANCHE);

        uint256 productTrancheTokensBalanceAfter = wavax.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceAfter = wavax.balanceOf(address(user1));

        assertEq(productTrancheTokensBalanceBefore, wavaxToDeposit);
        assertEq(productTrancheTokensBalanceAfter, 0); // since there is only one deposit

        assertEq(userTrancheTokensBalanceAfter, userTrancheTokensBalanceBefore + wavaxToDeposit);
    }

    function testClaimExcess_ShouldTransferJuniorTrancheTokens() public {
        console.log("should transfer the excess junior tranche tokens to the user");

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        uint256 productTrancheTokensBalanceBefore = usdc.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceBefore = usdc.balanceOf(address(user1));

        user1.claimExcess(JUNIOR_TRANCHE);

        uint256 productTrancheTokensBalanceAfter = usdc.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceAfter = usdc.balanceOf(address(user1));

        assertEq(productTrancheTokensBalanceBefore, usdcToDeposit);
        assertEq(productTrancheTokensBalanceAfter, 0); // since there is only one deposit

        assertEq(userTrancheTokensBalanceAfter, userTrancheTokensBalanceBefore + usdcToDeposit);
    }

    function testClaimExcess_ShouldSetClaimedTrue_SeniorTranche() public {
        console.log("should set `claimed` to `true` once claimed");

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        DataTypes.Investor memory investorDetailsBefore = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        user1.claimExcess(JUNIOR_TRANCHE);
        DataTypes.Investor memory investorDetailsAfter = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));

        assertEq(investorDetailsBefore.claimed, false);
        assertEq(investorDetailsAfter.claimed, true);
    }

    function testClaimExcess_ShouldSetClaimedTrue_JuniorTranche() public {
        console.log("should set `claimed` to `true` once claimed");

        _depositWarpInvestAndSetApproval(user1, wavaxToDeposit, SENIOR_TRANCHE);

        DataTypes.Investor memory investorDetailsBefore = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        user1.claimExcess(SENIOR_TRANCHE);
        DataTypes.Investor memory investorDetailsAfter = sut.getInvestorDetails(SENIOR_TRANCHE, address(user1));

        assertEq(investorDetailsBefore.claimed, false);
        assertEq(investorDetailsAfter.claimed, true);
    }

    function testClaimExcess_ShouldRevert_IfAlreadyClaimed_JuniorTranche() public {
        console.log("should revert when tried to claim more than once");

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        user1.claimExcess(JUNIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_ALREADY_CLAIMED));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testClaimExcess_ShouldRevert_IfAlreadyClaimed_SeniorTranche() public {
        console.log("should revert when tried to claim more than once");

        _depositWarpInvestAndSetApproval(user1, wavaxToDeposit, SENIOR_TRANCHE);

        user1.claimExcess(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_ALREADY_CLAIMED));
        user1.claimExcess(SENIOR_TRANCHE);
    }

    function testClaimExcess_ShouldEmitExcessClaimedEvent_SeniorTranche() public {
        console.log("should emit `ExcessClaimed` event when claimed excess from Senior tranche");

        _depositWarpInvestAndSetApproval(user1, wavaxToDeposit, SENIOR_TRANCHE);

        vm.expectEmit(true, true, false, true);
        emit ExcessClaimed(SENIOR_TRANCHE, 0, 0, wavaxToDeposit, address(user1));
        user1.claimExcess(SENIOR_TRANCHE);
    }

    function testClaimExcess_ShouldEmitExcessClaimedEvent_JuniorTranche() public {
        console.log("should emit `ExcessClaimed` event when claimed excess from Junior tranche");

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        vm.expectEmit(true, true, false, true);
        emit ExcessClaimed(JUNIOR_TRANCHE, 1, 0, usdcToDeposit * 10 ** 12, address(user1));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function _depositWarpInvestAndSetApproval(FEYProductUser _user, uint256 _amount, DataTypes.Tranche _tranche)
        internal
    {
        _deposit(_user, _amount, _tranche);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
    }
}
