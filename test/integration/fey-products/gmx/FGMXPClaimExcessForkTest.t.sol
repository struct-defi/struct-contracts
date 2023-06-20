pragma solidity 0.8.11;

import "@interfaces/IGMXYieldSource.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-products/gmx/GMXProductBaseTestSetupLive.sol";

contract FGMXPClaimExcessForkTest is GMXProductBaseTestSetupLive {
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;
    uint256 private wavaxToBeInvested = 224847521055007055319;
    uint256 private usdcToBeInvested = 27021141;

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

    function makeInitialDeposits() internal {
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, JUNIOR_TRANCHE, usdc);
    }

    function testForkClaimExcess_ShouldTransferExcessJuniorTrancheTokens() public {
        console.log("should transfer excess junior tranche tokens to the caller");

        _depositWarpInvestAndSetApproval(user1, 3000e6, JUNIOR_TRANCHE, usdc);
        (, uint256 excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user1));

        uint256 productTrancheTokensBalanceBefore = usdc.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceBefore = usdc.balanceOf(address(user1));

        user1.claimExcess(JUNIOR_TRANCHE);

        uint256 productTrancheTokensBalanceAfter = usdc.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceAfter = usdc.balanceOf(address(user1));

        assertEq(productTrancheTokensBalanceAfter, productTrancheTokensBalanceBefore - (excess / 10 ** 12));
        assertEq(userTrancheTokensBalanceAfter, userTrancheTokensBalanceBefore + (excess / 10 ** 12));
    }

    function testForkClaimExcess_ShouldTransferExcessJuniorTrancheTokens_DepositFor() public {
        console.log(
            "should transfer excess junior tranche tokens to the caller not to the depositor when depositFor is used"
        );
        /// User1 is depositing on behalf of User2
        /// User2 should be able claim excess.
        _depositFor(user1, 3000e6, JUNIOR_TRANCHE, user2);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        user2.setApprovalForAll(IERC1155(address(spToken)), address(sut));
        (, uint256 excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user2));

        uint256 productTrancheTokensBalanceBefore = usdc.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceBefore = usdc.balanceOf(address(user2));

        user2.claimExcess(JUNIOR_TRANCHE);

        uint256 productTrancheTokensBalanceAfter = usdc.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceAfter = usdc.balanceOf(address(user2));

        assertEq(productTrancheTokensBalanceAfter, productTrancheTokensBalanceBefore - (excess / 10 ** 12));
        assertEq(userTrancheTokensBalanceAfter, userTrancheTokensBalanceBefore + (excess / 10 ** 12));

        /// Should revert when called by the depositor
        vm.expectRevert(abi.encodePacked(Errors.VE_NO_EXCESS));
        user1.claimExcess(JUNIOR_TRANCHE);
    }

    function testForkClaimExcess_ShouldBurnJuniorTrancheSPTokens() public {
        console.log("should burn the user share of junior tranche SPTokens");

        _depositWarpInvestAndSetApproval(user1, 3000e6, JUNIOR_TRANCHE, usdc);
        (, uint256 excess) = sut.getUserInvestmentAndExcess(JUNIOR_TRANCHE, address(user1));

        uint256 spTokenBalanceBefore = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));

        user1.claimExcess(JUNIOR_TRANCHE);

        uint256 spTokenBalanceAfter = spToken.balanceOf(address(user1), uint256(JUNIOR_TRANCHE));

        assertEq(spTokenBalanceBefore, 3000e18);
        assertEq(spTokenBalanceAfter, spTokenBalanceBefore - excess);
    }

    function testForkClaimExcess_ShouldTransferExcessSeniorTrancheTokens() public {
        console.log("should transfer excess senior tranche tokens to the caller");

        _depositWarpInvestAndSetApproval(user1, 300e18, SENIOR_TRANCHE, wavax);
        (, uint256 excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user1));

        uint256 productTrancheTokensBalanceBefore = wavax.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceBefore = wavax.balanceOf(address(user1));

        user1.claimExcess(SENIOR_TRANCHE);

        uint256 productTrancheTokensBalanceAfter = wavax.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceAfter = wavax.balanceOf(address(user1));

        assertEq(productTrancheTokensBalanceAfter, productTrancheTokensBalanceBefore - (excess));
        assertEq(userTrancheTokensBalanceAfter, userTrancheTokensBalanceBefore + (excess));
    }

    function testForkClaimExcess_ShouldTransferExcessSeniorTrancheTokens_DepositFor() public {
        console.log(
            "should transfer excess senior tranche tokens to the caller not to the depositor when depositFor is used"
        );
        /// User1 is depositing on behalf of User2
        /// User2 should be able claim excess.
        _depositFor(user1, 300e18, SENIOR_TRANCHE, user2);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        user2.setApprovalForAll(IERC1155(address(spToken)), address(sut));
        (, uint256 excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user2));

        uint256 productTrancheTokensBalanceBefore = wavax.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceBefore = wavax.balanceOf(address(user2));

        user2.claimExcess(SENIOR_TRANCHE);

        uint256 productTrancheTokensBalanceAfter = wavax.balanceOf(address(sut));
        uint256 userTrancheTokensBalanceAfter = wavax.balanceOf(address(user2));

        assertEq(productTrancheTokensBalanceAfter, productTrancheTokensBalanceBefore - (excess));
        assertEq(userTrancheTokensBalanceAfter, userTrancheTokensBalanceBefore + (excess));

        /// Should revert when called by the depositor
        vm.expectRevert(abi.encodePacked(Errors.VE_NO_EXCESS));
        user1.claimExcess(SENIOR_TRANCHE);
    }

    function testForkClaimExcess_ShouldBurnSeniorTrancheSPTokens() public {
        console.log("should burn senior tranche SPToken share of the user");

        _depositWarpInvestAndSetApproval(user1, 300e18, SENIOR_TRANCHE, wavax);
        (, uint256 excess) = sut.getUserInvestmentAndExcess(SENIOR_TRANCHE, address(user1));

        uint256 spTokenBalanceBefore = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));

        user1.claimExcess(SENIOR_TRANCHE);

        uint256 spTokenBalanceAfter = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE));

        assertEq(spTokenBalanceBefore, 400e18);
        assertEq(spTokenBalanceAfter, spTokenBalanceBefore - excess);
    }

    function _mockYieldSourceCalls() internal {
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.supplyTokens.selector),
            abi.encode(wavaxToBeInvested, usdcToBeInvested)
        );
    }

    function _depositWarpInvestAndSetApproval(
        FEYProductUser _user,
        uint256 _amount,
        DataTypes.Tranche _tranche,
        IERC20Metadata _token
    ) internal {
        _deposit(_user, _amount, _tranche, _token);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
    }
}
