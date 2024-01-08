pragma solidity 0.8.11;

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "@interfaces/IGMXYieldSource.sol";
import "@external/gmx/IVaultPriceFeed.sol";
import "@external/gmx/IFastPriceFeed.sol";

import "../../../common/fey-products/gmx/FEYProductBaseTestSetup.sol";

contract FGMXPInvest_UnitTest is FEYProductBaseTestSetup {
    IGMXYieldSource public yieldSource;
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    event Invested(
        uint256 _trancheTokensInvestedSenior,
        uint256 _trancheTokensInvestedJunior,
        uint256 _trancheTokensInvestableSenior,
        uint256 _trancheTokensInvestableJunior
    );

    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testInvest_RevertInvalidState() public {
        console.log("should revert when tried to invest when the tranche is not started");
        vm.expectRevert(abi.encodePacked(Errors.VE_TRANCHE_NOT_STARTED));
        user1.invest();
    }

    function testInvest_RevertWhenLocalPaused() public {
        console.log("ID: Pr_Inv_20");

        console.log("should revert when the contract is paused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.invest();
    }

    function testInvest_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_Inv_21");

        console.log("should revert when the contract is paused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.invest();
    }

    function testInvest_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_Inv_21");

        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.invest();

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_TRANCHE_NOT_STARTED));
        user1.invest();
    }

    function testInvest_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_Inv_22");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.invest();

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_TRANCHE_NOT_STARTED));
        user1.invest();
    }

    function testInvest_UpdateStateIfNoDeposits() public {
        vm.warp(block.timestamp + 15 minutes);
        console.log(
            "should update the product status, total deposits and tokens excess when there are no deposits in both the tranches"
        );
        user1.invest();

        assertEq(uint8(sut.getCurrentState()), 2);

        DataTypes.TrancheInfo memory seniorTrancheInfo = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory juniorTrancheInfo = sut.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(seniorTrancheInfo.tokensInvestable, 0);
        assertEq(seniorTrancheInfo.tokensExcess, 0);
        assertEq(juniorTrancheInfo.tokensInvestable, 0);
        assertEq(juniorTrancheInfo.tokensExcess, 0);
    }

    function testInvest_UpdateStateIfNoDepositsSenior() public {
        console.log(
            "should update the product status, total deposits and tokens excess when there are no deposits in senior tranche"
        );
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        assertEq(uint8(sut.getCurrentState()), 2);

        DataTypes.TrancheInfo memory seniorTrancheInfo = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory juniorTrancheInfo = sut.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(seniorTrancheInfo.tokensInvestable, 0);
        assertEq(seniorTrancheInfo.tokensExcess, 0);
        assertEq(juniorTrancheInfo.tokensInvestable, 0);
        assertEq(juniorTrancheInfo.tokensExcess, usdcToDeposit * 1e12);
    }

    function testInvest_EmitInvestedZeroIfNoDepositsSenior() public {
        console.log(
            "should emit an Invested event with all four values as zero when there are no deposits in senior tranche"
        );
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        vm.warp(block.timestamp + 15 minutes);

        vm.expectEmit(true, true, true, true);
        emit Invested(0, 0, 0, 0);
        user1.invest();

        assertEq(uint8(sut.getCurrentState()), 2);
    }

    function testInvest_UpdateStateIfNoDepositsJunior() public {
        console.log(
            "should update the product status, total deposits and tokens excess when there are no deposits in junior tranche"
        );

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();

        assertEq(uint8(sut.getCurrentState()), 2);

        DataTypes.TrancheInfo memory seniorTrancheInfo = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory juniorTrancheInfo = sut.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(seniorTrancheInfo.tokensInvestable, 0);
        assertEq(seniorTrancheInfo.tokensExcess, wavaxToDeposit);
        assertEq(juniorTrancheInfo.tokensInvestable, 0);
        assertEq(juniorTrancheInfo.tokensExcess, 0);
    }

    function testInvest_RevertInvalidPrice() public {
        console.log("GMX_Pr_Inv_1");
        console.log("should revert when the senior price is invalid");
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        vm.warp(block.timestamp + 15 minutes);

        IVaultPriceFeed VAULT_PRICE_FEED = IVaultPriceFeed(0x27e99387af40e5CA9CE21418552f15F02C8C57E7);
        IFastPriceFeed FAST_PRICE_FEED = IFastPriceFeed(0xE547CaDbe081749e5b3DC53CB792DfaEA2D02fD2);

        uint256 _vaultPriceFeedResponse = 1 * 10 ** 8;
        // fast price is 6% higher than vault price
        uint256 _fastPriceFeedResponse = 106 * 10 ** 28;
        uint256 _priceDecimals = 8;

        vm.mockCall(
            address(VAULT_PRICE_FEED),
            abi.encodeWithSelector(IVaultPriceFeed.getLatestPrimaryPrice.selector),
            abi.encode(_vaultPriceFeedResponse)
        );

        vm.mockCall(
            address(VAULT_PRICE_FEED),
            abi.encodeWithSelector(IVaultPriceFeed.priceDecimals.selector),
            abi.encode(_priceDecimals)
        );

        vm.mockCall(
            address(FAST_PRICE_FEED),
            abi.encodeWithSelector(IFastPriceFeed.prices.selector),
            abi.encode(_fastPriceFeedResponse)
        );

        vm.expectRevert(abi.encodePacked(Errors.PFE_INVALID_SR_PRICE));
        user1.invest();
    }
}
