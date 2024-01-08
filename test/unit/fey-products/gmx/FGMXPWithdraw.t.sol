pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";
import "@mocks/MockERC20.sol";

import "../../../common/fey-products/gmx/FEYProductBaseTestSetup.sol";

contract FGMXPWithdraw_UnitTest is FEYProductBaseTestSetup {
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    uint256 private usdcValueDecimalScalingFactor = 1e12;

    event Withdrawn(DataTypes.Tranche _tranche, uint256 _amount, address indexed _user);

    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testWithdraw_RevertIfInvalidState() public {
        console.log("should revert when tried to claim excess when the tranche is not yet invested");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_RevertIfNoDeposits() public {
        vm.warp(block.timestamp + 15 minutes);
        console.log("should revert when there is no tokens to withdraw");
        user1.invest();

        vm.expectRevert(abi.encodePacked(Errors.VE_INSUFFICIENT_BAL));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INSUFFICIENT_BAL));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_RevertIfExcessNotClaimed() public {
        console.log("should revert when tried to withdraw before claiming excess");

        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_NOT_CLAIMED_YET));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_ShouldRevertIfNotApproved() public {
        console.log("should revert when tried to withdraw without approving the product contract");
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        sut.setTokensInvestable(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(JUNIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);

        vm.expectRevert(abi.encodePacked("NOT_AUTHORIZED"));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_ShouldRevertIfTriedToWithdrawMultiple() public {
        console.log("should revert when tried to withdraw more than once");
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        sut.setTokensInvestable(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        sut.setTokensInvestable(SENIOR_TRANCHE, wavaxToDeposit);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(JUNIOR_TRANCHE, address(user1), true);
        sut.setExcessClaimed(SENIOR_TRANCHE, address(user1), true);

        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        sut.setTokensAtMaturity(SENIOR_TRANCHE, wavaxToDeposit);

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        // Withdraw twice from Junior tranche
        user1.withdraw(JUNIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INSUFFICIENT_BAL));
        user1.withdraw(JUNIOR_TRANCHE);

        // Withdraw twice from senior tranche
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INSUFFICIENT_BAL));
        user1.withdraw(SENIOR_TRANCHE);
    }

    function testWithdraw_RevertWhenLocalPaused() public {
        console.log("ID: Pr_Wi_25");
        console.log("should revert when the contract is paused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_Wi_26");

        console.log("should revert when the contract is paused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_Wi_27");

        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.withdraw(JUNIOR_TRANCHE);

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_Wi_28");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.withdraw(JUNIOR_TRANCHE);

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.withdraw(SENIOR_TRANCHE);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.withdraw(JUNIOR_TRANCHE);
    }

    function testWithdraw_ShouldBurnSPTokensTrancheJunior() public {
        console.log("should burn the junior tranche SP tokens");
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        sut.setTokensInvestable(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(JUNIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 _juniorTrancheSPTokenBalanceBefore = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));
        user1.withdraw(JUNIOR_TRANCHE);

        uint256 _juniorTrancheSPTokenBalanceAfter = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));

        assertEq(
            _juniorTrancheSPTokenBalanceBefore - _juniorTrancheSPTokenBalanceAfter,
            usdcToDeposit * usdcValueDecimalScalingFactor,
            "Validate Balance Change"
        );
        assertEq(_juniorTrancheSPTokenBalanceAfter, 0, "Burn All SPTokens");
    }

    function testWithdraw_ShouldBurnSPTokensTrancheSenior() public {
        console.log("should burn the senior tranche SP tokens");
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        sut.setTokensInvestable(SENIOR_TRANCHE, wavaxToDeposit);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(SENIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(SENIOR_TRANCHE, wavaxToDeposit);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 _spTokenBalanceTrancheSeniorBefore = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));
        user1.withdraw(SENIOR_TRANCHE);
        uint256 _seniorTrancheSPTokenBalanceAfter = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));

        assertEq(
            _spTokenBalanceTrancheSeniorBefore - _seniorTrancheSPTokenBalanceAfter,
            wavaxToDeposit,
            "ValidateBalanceChange"
        );
        assertEq(_seniorTrancheSPTokenBalanceAfter, 0, "Burn All SPTokens");
    }

    function testWithdraw_ShouldTransferTrancheTokensSenior() public {
        console.log("should transfer the matured senior tranche tokens to the user");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        sut.setTokensInvestable(SENIOR_TRANCHE, wavaxToDeposit);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(SENIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(SENIOR_TRANCHE, wavaxToDeposit);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 trancheTokenSeniorProductBalanceBefore = wavax.balanceOf(address(sut));
        uint256 trancheTokenSeniorUserBalanceBefore = wavax.balanceOf(address(user1));

        user1.withdraw(SENIOR_TRANCHE);

        uint256 trancheTokenSeniorProductBalanceAfter = wavax.balanceOf(address(sut));
        uint256 trancheTokenSeniorUserBalanceAfter = wavax.balanceOf(address(user1));

        assertEq(trancheTokenSeniorProductBalanceBefore, wavaxToDeposit, "Product Tranche Tokens Balance Before");
        assertEq(trancheTokenSeniorProductBalanceAfter, 0, "Product Tranche Tokens Balance After"); // since there is only one deposit

        assertEq(
            trancheTokenSeniorUserBalanceAfter,
            trancheTokenSeniorUserBalanceBefore + wavaxToDeposit,
            "User Tranche Tokens Balance After"
        );
    }

    function testWithdraw_ShouldTransferTrancheTokensJunior() public {
        console.log("should transfer the matured junior tranche tokens to the user");

        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        sut.setTokensInvestable(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(JUNIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 trancheTokenSeniorProductBalanceBefore = usdc.balanceOf(address(sut));
        uint256 trancheTokenSeniorUserBalanceBefore = usdc.balanceOf(address(user1));

        user1.withdraw(JUNIOR_TRANCHE);
        uint256 trancheTokenSeniorProductBalanceAfter = usdc.balanceOf(address(sut));
        uint256 trancheTokenSeniorUserBalanceAfter = usdc.balanceOf(address(user1));

        assertEq(trancheTokenSeniorProductBalanceBefore, usdcToDeposit, "Product Tranche Tokens Balance Before");
        assertEq(trancheTokenSeniorProductBalanceAfter, 0, "Product Tranche Tokens Balance After"); // since there is only one deposit

        assertEq(
            trancheTokenSeniorUserBalanceAfter,
            trancheTokenSeniorUserBalanceBefore + usdcToDeposit,
            "User Tranche Tokens Balance After"
        );
    }

    function testWithdraw_ShouldEmitWithdrawnEvent_SeniorTranche() public {
        console.log("should emit `Withdrawn()` event when withdrawn from the senior tranche with the correct params");
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        sut.setTokensInvestable(SENIOR_TRANCHE, wavaxToDeposit);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(SENIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(SENIOR_TRANCHE, wavaxToDeposit);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(SENIOR_TRANCHE, wavaxToDeposit, address(user1));
        user1.withdraw(SENIOR_TRANCHE);
    }

    function testWithdraw_ShouldEmitWithdrawnEvent_JuniorTranche() public {
        console.log("should emit `Withdrawn()` event when withdrawn from the junior tranche with the correct params");
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        sut.setTokensInvestable(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setExcessClaimed(JUNIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor, address(user1));
        user1.withdraw(JUNIOR_TRANCHE);
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
