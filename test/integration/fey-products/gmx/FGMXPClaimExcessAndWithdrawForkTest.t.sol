// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";
import "@mocks/MockERC20.sol";

import "../../../common/fey-products/gmx/GMXProductBaseTestSetupLive.sol";

contract FGMXPClaimExcessAndWithdrawForkTest is GMXProductBaseTestSetupLive {
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;
    uint256 private wavaxToBeInvested = 224847521055007055319;
    uint256 private usdcToBeInvested = 27021141;

    uint256 private usdcValueDecimalScalingFactor = 1e12;

    event Withdrawn(DataTypes.Tranche _tranche, uint256 _amount, address indexed _user);

    event ExcessClaimed(
        DataTypes.Tranche _tranche,
        uint256 _spTokenId,
        uint256 _userInvested,
        uint256 _excessAmount,
        address indexed _user
    );

    function setUp() public virtual override {
        /// Remove hardcoding and move it to use env string - vm.envString("MAINNET_RPC")
        vm.createSelectFork("https://api.avax.network/ext/bc/C/rpc", 24540193);

        super.setUp();
        makeInitialDeposits();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        investTestsFixture(wavax, usdc, 1000e18, 20000e18);

        _mockYieldSourceCalls();
    }

    function testClaimExcessAndWithdraw_Status1_RevertIfNoExcessNoWithdrawal() public {
        console.log("ID: Pr_CEAW_2");
        console.log(
            "should revert with error VE_NO_WITHDRAW_OR_EXCESS is user has no excess nor withdrawal in product status 1"
        );

        _warpInvest();

        vm.expectRevert(abi.encodePacked(Errors.VE_NO_WITHDRAW_OR_EXCESS));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_Status2_RevertIfNoExcessNoWithdrawal() public {
        console.log("ID: Pr_CEAW_3");
        console.log(
            "should revert with error VE_NO_WITHDRAW_OR_EXCESS is user has no excess nor withdrawal in product status 2"
        );

        _warpInvest();
        sut.setCurrentState(DataTypes.State.WITHDRAWN);

        vm.expectRevert(abi.encodePacked(Errors.VE_NO_WITHDRAW_OR_EXCESS));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_Success_Status2_OnlyExcessNoWithdraw1_Emit() public {
        console.log("ID: Pr_CEAW_4");
        console.log("should emit event ExcessClaimed if the user has excess but no withdrawal in product status 2");
        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE, usdc);
        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        vm.expectEmit(true, true, true, true);
        emit ExcessClaimed(JUNIOR_TRANCHE, 1, 0, usdcToDeposit * usdcValueDecimalScalingFactor, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testFailClaimExcessAndWithdraw_Status2_SuccessOnlyExcessNoWithdraw2_Emit() public {
        console.log("ID: Pr_CEAW_4");
        console.log("should NOT emit event Withdrawn if the user has excess but no withdrawal in product status 2");
        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE, usdc);
        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        // checking event is not emitted
        vm.expectEmit(false, false, false, false);
        emit Withdrawn(JUNIOR_TRANCHE, 0, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_Success_Status1_OnlyExcessNoWithdraw1_Emit() public {
        console.log("ID: Pr_CEAW_5");
        console.log("should emit event ExcessClaimed if the user has excess but no withdrawal in product status 1");
        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE, usdc);
        vm.expectEmit(true, true, true, true);
        emit ExcessClaimed(JUNIOR_TRANCHE, 1, 0, usdcToDeposit * usdcValueDecimalScalingFactor, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testFailClaimExcessAndWithdraw_Status1_SuccessOnlyExcessNoWithdraw2_Emit() public {
        console.log("ID: Pr_CEAW_5");
        console.log("should NOT emit event Withdrawn if the user has excess but no withdrawal in product status 1");
        _depositWarpInvestAndSetApproval(user1, usdcToDeposit, JUNIOR_TRANCHE, usdc);
        // checking event is not emitted
        vm.expectEmit(false, false, false, false);
        emit Withdrawn(JUNIOR_TRANCHE, 0, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_SuccessOnlyWithdrawNoExcess_Emit() public {
        console.log("ID: Pr_CEAW_6");
        console.log("should emit event Withdrawn if the user has no excess but a withdrawal");
        uint256 usdcDepositWithinThreshold = usdcToDeposit / 10;
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user1, usdcDepositWithinThreshold, JUNIOR_TRANCHE, usdc);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcDepositWithinThreshold * usdcValueDecimalScalingFactor);
        _warpInvest();
        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        (, uint256 excessJr) = user1.getInvestedAndExcess(JUNIOR_TRANCHE);
        assertEq(excessJr, 0, "No Jr Tranche Excess");
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
        // not checking data
        vm.expectEmit(true, true, true, false);
        emit Withdrawn(JUNIOR_TRANCHE, 0, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_SuccessOnlyWithdrawExcessClaimed_Emit() public {
        console.log("ID: Pr_CEAW_7");
        console.log("should emit event Withdrawn if the user has already claimed excess but not withdrawal");
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE, usdc);
        sut.setExcessClaimed(JUNIOR_TRANCHE, address(user1), true);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        _warpInvest();
        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        DataTypes.Investor memory user1DetailsJr = sut.getInvestorDetails(JUNIOR_TRANCHE, address(user1));
        assertEq(user1DetailsJr.claimed, true, "User already claimed Jr Tranche excess");
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
        // not checking data
        vm.expectEmit(true, true, true, false);
        emit Withdrawn(JUNIOR_TRANCHE, 0, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_SuccessExcessAndWithdraw_Emit() public {
        console.log("ID: Pr_CEAW_8");
        console.log("should emit events ExcessClaimed and Withdrawn if the user has an excess and a withdrawal");
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE, usdc);
        _warpInvest();

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        sut.setTokensAtMaturity(SENIOR_TRANCHE, wavaxToDeposit);

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
        // not checking data
        vm.expectEmit(true, true, true, false);
        emit ExcessClaimed(JUNIOR_TRANCHE, 1, 0, 0, address(user1));
        // not checking data
        vm.expectEmit(true, true, true, false);
        emit Withdrawn(JUNIOR_TRANCHE, 0, address(user1));
        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
    }

    function testClaimExcessAndWithdraw_Success_Status1_OnlyExcessNoWithdraw() public {
        console.log("ID: Pr_CEAW_9");
        console.log(
            "user SP token balance should be correct when the user has excess but no withdrawal in product status 1"
        );
        deal(address(usdc), address(user1), usdcToDeposit);
        uint256 trancheTokenBalanceBeforeDeposit = IERC20(usdc).balanceOf(address(user1));
        user1.increaseAllowance(address(usdc), usdcToDeposit);
        user1.depositToJunior(usdcToDeposit);

        uint256 trancheTokenBalanceAfterDeposit = IERC20(usdc).balanceOf(address(user1));
        _warpInvest();

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
        uint256 trancheTokenBalanceAfterClaim = IERC20(usdc).balanceOf(address(user1));
        assertEq(
            trancheTokenBalanceBeforeDeposit,
            trancheTokenBalanceAfterClaim,
            "trancheTokenBalanceBeforeDeposit == trancheTokenBalanceAfterClaim"
        );
        assertTrue(
            trancheTokenBalanceAfterDeposit < trancheTokenBalanceAfterClaim,
            "trancheTokenBalanceAfterDeposit < trancheTokenBalanceAfterClaim"
        );
        assertTrue(
            trancheTokenBalanceBeforeDeposit > trancheTokenBalanceAfterDeposit,
            "trancheTokenBalanceBeforeDeposit > trancheTokenBalanceAfterDeposit"
        );
    }

    function testClaimExcessAndWithdraw_Success_Status1_OnlyWithdrawNoExcess() public {
        console.log("ID: Pr_CEAW_10");
        console.log("user SP token balance should be correct when the user has withdrawal but no excess");
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);

        uint256 usdcDepositWithinThreshold = usdcToDeposit / 10;
        deal(address(usdc), address(user1), usdcDepositWithinThreshold);

        uint256 trancheTokenBalanceBeforeDeposit = IERC20(usdc).balanceOf(address(user1));

        user1.increaseAllowance(address(usdc), usdcDepositWithinThreshold);
        user1.depositToJunior(usdcDepositWithinThreshold);
        uint256 trancheTokenBalanceAfterDeposit = IERC20(usdc).balanceOf(address(user1));

        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcDepositWithinThreshold * usdcValueDecimalScalingFactor);
        _warpInvest();

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        (, uint256 excessJr) = user1.getInvestedAndExcess(JUNIOR_TRANCHE);
        assertEq(excessJr, 0, "No Jr Tranche Excess");

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
        uint256 trancheTokenBalanceAfterWithdraw = IERC20(usdc).balanceOf(address(user1));
        assertTrue(
            trancheTokenBalanceAfterDeposit < trancheTokenBalanceAfterWithdraw,
            "trancheTokenBalanceAfterDeposit < trancheTokenBalanceAfterWithdraw"
        );
        assertTrue(
            trancheTokenBalanceBeforeDeposit > trancheTokenBalanceAfterDeposit,
            "trancheTokenBalanceBeforeDeposit > trancheTokenBalanceAfterDeposit"
        );
    }

    function testClaimExcessAndWithdraw_Success_Status1_ExcessAndWithdraw() public {
        console.log("ID: Pr_CEAW_11");
        console.log("user SP token balance should be correct when the user has withdrawal and excess");
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);

        deal(address(usdc), address(user1), usdcToDeposit);

        uint256 trancheTokenBalanceBeforeDeposit = IERC20(usdc).balanceOf(address(user1));

        user1.increaseAllowance(address(usdc), usdcToDeposit);
        user1.depositToJunior(usdcToDeposit);
        uint256 trancheTokenBalanceAfterDeposit = IERC20(usdc).balanceOf(address(user1));

        sut.setTokensAtMaturity(JUNIOR_TRANCHE, usdcToDeposit * usdcValueDecimalScalingFactor);
        _warpInvest();

        sut.setCurrentState(DataTypes.State.WITHDRAWN);
        (, uint256 excessJr) = user1.getInvestedAndExcess(JUNIOR_TRANCHE);
        assertTrue(excessJr != 0, "Has Jr Tranche Excess");

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        user1.claimExcessAndWithdraw(JUNIOR_TRANCHE);
        uint256 trancheTokenBalanceAfterClaimAndWithdraw = IERC20(usdc).balanceOf(address(user1));
        assertTrue(
            trancheTokenBalanceAfterDeposit < trancheTokenBalanceAfterClaimAndWithdraw,
            "trancheTokenBalanceAfterDeposit < trancheTokenBalanceAfterClaimAndWithdraw"
        );
        assertTrue(
            trancheTokenBalanceBeforeDeposit > trancheTokenBalanceAfterDeposit,
            "trancheTokenBalanceBeforeDeposit > trancheTokenBalanceAfterDeposit"
        );
    }

    function makeInitialDeposits() internal {
        _deposit(user2, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, JUNIOR_TRANCHE, usdc);
    }

    function _depositWarpInvestAndSetApproval(
        FEYProductUser _user,
        uint256 _amount,
        DataTypes.Tranche _tranche,
        IERC20Metadata _token
    ) internal {
        _deposit(_user, _amount, _tranche, _token);
        _warpInvest();

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
    }

    function _warpInvest() internal {
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();
    }

    function _mockYieldSourceCalls() internal {
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.recompoundRewards.selector),
            abi.encodePacked(true)
        );
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.supplyTokens.selector),
            abi.encode(wavaxToBeInvested, usdcToBeInvested)
        );
    }
}
