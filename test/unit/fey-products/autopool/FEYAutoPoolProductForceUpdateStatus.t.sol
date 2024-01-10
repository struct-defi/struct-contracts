pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@core/libraries/types/DataTypes.sol";

import "../../../common/fey-products/autopool/FEYProductBaseTestSetup.sol";

contract FEYAutoPoolProductForceUpdateStatus_UnitTest is FEYProductBaseTestSetup {
    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    event RemovedFundsFromLP(uint256 _srTokensReceived, uint256 _jrTokensReceived, address indexed _user);

    event Invested(
        uint256 _trancheTokensInvestedSenior,
        uint256 _trancheTokensInvestedJunior,
        uint256 _trancheTokensInvestableSenior,
        uint256 _trancheTokensInvestableJunior
    );
    event StatusUpdated(DataTypes.State status);

    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testForceUpdateStatus_ShouldEmitInvestedEvent() public {
        console.log("should emit Invested event with all values = 0");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);

        vm.warp(block.timestamp + 20 days);
        vm.expectEmit(true, true, true, true);
        emit Invested(0, 0, 0, 0);
        sut.forceUpdateStatusToWithdrawn();
    }

    function testForceUpdateStatus_ShouldEmitStatusUpdatedEvent() public {
        console.log("should emit StatusUpdated event");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);

        vm.warp(block.timestamp + 20 days);
        vm.expectEmit(true, true, true, true);
        emit StatusUpdated(DataTypes.State.WITHDRAWN);
        sut.forceUpdateStatusToWithdrawn();
    }

    function testForceUpdateStatus_ShouldEmitRemovedFundsFromLPEvent() public {
        console.log("should emit RemovedFundsFromLP event with all values = 0");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);

        vm.warp(block.timestamp + 20 days);
        vm.expectEmit(true, true, true, true);
        emit RemovedFundsFromLP(0, 0, address(this));
        sut.forceUpdateStatusToWithdrawn();
    }

    function testForceUpdateStatus_ShouldUpdateCurrentState() public {
        console.log("should set current state of the product to WITHDRAWN");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);

        vm.warp(block.timestamp + 20 days);

        sut.forceUpdateStatusToWithdrawn();
        assertEq(uint8(sut.getCurrentState()), uint8(DataTypes.State.WITHDRAWN));
    }

    function testForceUpdateStatus_ShouldUpdateTokenExcess() public {
        console.log("should update tokensExcess");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        vm.warp(block.timestamp + 10 days);

        DataTypes.TrancheInfo memory seniorTrancheInfoBefore = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory juniorTrancheInfoBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        sut.forceUpdateStatusToWithdrawn();

        DataTypes.TrancheInfo memory seniorTrancheInfoAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory juniorTrancheInfoAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(seniorTrancheInfoBefore.tokensExcess, 0, "seniorTrancheInfoBefore");
        assertEq(seniorTrancheInfoAfter.tokensExcess, wavaxToDeposit, "seniorTrancheInfoAfter");

        assertEq(juniorTrancheInfoBefore.tokensExcess, 0, "juniorTrancheInfoBefore");
        assertEq(juniorTrancheInfoAfter.tokensExcess, usdcToDeposit * 1e12, "juniorTrancheInfoAfter");
    }

    function testForceUpdateStatus_ShouldRevert_IfProductIsNotOpen() public {
        console.log("should revert if the Product state is not OPEN");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);

        sut.setCurrentState(DataTypes.State.INVESTED);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        sut.forceUpdateStatusToWithdrawn();
    }

    function testForceUpdateStatus_ShouldRevert_IfNotPast24Hours() public {
        console.log("should revert if the it has not been a day since the tranche start time");

        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE);
        _deposit(user1, usdcToDeposit, JUNIOR_TRANCHE);
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        sut.forceUpdateStatusToWithdrawn();
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
