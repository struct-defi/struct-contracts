pragma solidity 0.8.11;

import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-products/autopool/FEYProductBaseTestSetup.sol";

contract FEYAutoPoolProductInvest_UnitTest is FEYProductBaseTestSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testInvest_RevertIfAutoPoolDepositsPaused() public {
        console.log("should revert when autopool vault deposits are paused");
        vm.mockCall(address(autoPoolVault), abi.encodeWithSelector(0x27042b84), abi.encode(true));
        vm.expectRevert(abi.encodePacked(Errors.VE_AUTOPOOLVAULT_PAUSED));
        user1.invest();
    }
}
