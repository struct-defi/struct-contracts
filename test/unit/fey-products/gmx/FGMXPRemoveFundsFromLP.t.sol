pragma solidity 0.8.11;

import "@core/libraries/helpers/Errors.sol";
import "../../../common/fey-products/gmx/FEYProductBaseTestSetup.sol";

contract FGMXPRemoveFundsFromLP is FEYProductBaseTestSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testRemoveFundsFromLP_RevertInvalidState() public {
        console.log("should revert when tried to remove funds from LP before invested");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.removeFundsFromLP();
    }

    function testRemoveFundsFromLP_RevertWhenLocalPaused() public {
        console.log("ID: Pr_RFFLP_20");

        console.log("should revert when the contract is paused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.removeFundsFromLP();
    }

    function testRemoveFundsFromLP_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_RFFLP_21");

        console.log("should revert when the contract is paused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.removeFundsFromLP();
    }

    function testRemoveFundsFromLP_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_RFFLP_22");

        console.log("should revert with a different error message when the contract is unpaused locally");

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.removeFundsFromLP();

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.removeFundsFromLP();
    }

    function testRemoveFundsFromLP_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_RFFLP_23");

        console.log("should revert with a different error message when the contract is unpaused globally");

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.removeFundsFromLP();

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.removeFundsFromLP();
    }
}
