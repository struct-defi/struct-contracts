pragma solidity 0.8.11;

import "@interfaces/IFEYFactory.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-products/autopool/FEYProductBaseTestSetup.sol";

contract FEYAutoPoolProductDepositWithAVAX_UnitTest is FEYProductBaseTestSetup {
    uint256 private _depositAmount = 1e18;
    uint256 private userBalance = 100e18;

    event Deposit(address indexed dst, uint256 wad);

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function depositAVAXToSenior() internal {
        deal(address(user1), userBalance);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDepositAP_AVAX_SeniorTranche_RevertInvalidInputAmount() external {
        console.log("Deposit transaction reverts if user passes _initialDepositAmount not equal to msg.value");
        deal(address(user1), 100e18);
        // _depositAmount is different from AVAX value sent
        uint256 _value = 2e18;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_INPUT_AMOUNT));
        user1.depositAvaxToSenior(_depositAmount, _value);
    }

    function testDepositAP_AVAX_SeniorTranche_RevertInsufficientFunds() external {
        console.log("Deposit transaction reverts if user has no AVAX");
        vm.expectRevert();
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDepositAP_AVAX_RevertWhenLocalPaused() public {
        console.log("ID: Pr_Dep_18");

        console.log("should revert when the contract is paused locally");
        deal(address(user1), _depositAmount);

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDepositAP_AVAX_RevertWhenGlobalPaused() public {
        console.log("ID: Pr_Dep_19");

        console.log("should revert when the contract is paused globally");
        deal(address(user1), _depositAmount);

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testFailDeposit_AVAX_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("ID: Pr_Dep_20");

        console.log("should revert with a different error message when the contract is unpaused locally");
        deal(address(user1), _depositAmount);

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);

        pauser.localUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testFailDeposit_AVAX_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("ID: Pr_Dep_21");
        console.log("should revert with a different error message when the contract is unpaused globally");
        deal(address(user1), _depositAmount);

        pauser.globalPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);

        pauser.globalUnpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDepositAP_AVAX_JuniorTranche_RevertInvalidNativeTokenDeposit() external {
        console.log("ID: Pr_Dep_26");
        console.log("Reverts with error VE_INVALID_NATIVE_TOKEN_DEPOSIT if user deposits AVAX to non-wAVAX tranche");
        uint256 _value = 2e6;
        deal(address(user1), _value);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_NATIVE_TOKEN_DEPOSIT));
        user1.depositAvaxToJunior(_value, _value);
    }

    function testDepositAP_AVAX_SeniorTranche_ProductContractConstantAVAXBalance() external {
        console.log("AVAX balance of product contract should be the same before and after AVAX deposit");
        uint256 contractProductAVAXBalanceBefore = user1.balanceOf();
        depositAVAXToSenior();
        uint256 contractProductAVAXBalanceAfter = user1.balanceOf();
        assertEq(contractProductAVAXBalanceBefore, contractProductAVAXBalanceAfter);
    }

    function testDepositAP_AVAX_SeniorTranche_UserSubtractedAVAXBalance() external {
        console.log("AVAX balance of the user should be equal to balance before less _depositAmount");
        deal(address(user1), userBalance);
        uint256 userAVAXBalanceBefore = address(user1).balance;
        assertEq(userAVAXBalanceBefore, userBalance);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
        uint256 userAVAXBalanceAfter = address(user1).balance;
        assertEq(userAVAXBalanceBefore - _depositAmount, userAVAXBalanceAfter);
    }

    function testDepositAP_AVAX_SeniorTranche_InvestorDepositedNative() external {
        console.log("investorDetails.depositedNative should be true");
        depositAVAXToSenior();
        DataTypes.Investor memory _investorDetails = user1.getInvestorDetails(DataTypes.Tranche.Senior);
        assertEq(_investorDetails.depositedNative, true);
    }

    function testDepositAP_AVAX_SeniorTranche_EmitWeth9Deposit() external {
        console.log("Deposit with AVAX should emit Deposit event from WETH9 contract");
        deal(address(user1), userBalance);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        vm.expectEmit(false, true, true, true);
        emit Deposit(address(user1), _depositAmount);
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDepositAP_AVAX_SeniorTranche_RevertInvariantCheckFailed() public {
        console.log("Pr_Dep_28");
        console.log(
            "should revert with error VE_DEPOSIT_INVARIANT_CHECK if tranche tokens owned by product < SP token total supply - deposit avax to senior tranche"
        );
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        uint256 _amountToDeposit = 1e18;
        deal(address(user1), _amountToDeposit);

        vm.mockCall(address(wavax), abi.encodeWithSelector(wavax.balanceOf.selector), abi.encode(0));
        vm.expectRevert(abi.encodePacked(Errors.VE_DEPOSIT_INVARIANT_CHECK));
        vm.prank(address(user1));
        sut.deposit{value: _amountToDeposit}(SENIOR_TRANCHE, _amountToDeposit);
    }
}
