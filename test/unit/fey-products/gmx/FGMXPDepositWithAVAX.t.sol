pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@external/IWETH9.sol";
import "@mocks/MockERC20.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";

import "../../../common/fey-products/gmx/FEYProductBaseTestSetup.sol";

contract FGMXPDepositWithAVAX_UnitTest is FEYProductBaseTestSetup {
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

    function testDeposit_AVAX_SeniorTranche_RevertInvalidInputAmount() external {
        console.log("Deposit transaction reverts if user passes _initialDepositAmount not equal to msg.value");
        deal(address(user1), 100e18);
        // _depositAmount is different from AVAX value sent
        uint256 _value = 2e18;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_INPUT_AMOUNT));
        user1.depositAvaxToSenior(_depositAmount, _value);
    }

    function testDeposit_AVAX_SeniorTranche_RevertInsufficientFunds() external {
        console.log("Deposit transaction reverts if user has no AVAX");
        vm.expectRevert();
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDeposit_AVAX_RevertWhenLocalPaused() public {
        console.log("ID: Pr_Dep_18");

        console.log("should revert when the contract is paused locally");
        deal(address(user1), _depositAmount);

        pauser.localPause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDeposit_AVAX_RevertWhenGlobalPaused() public {
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

    function testDeposit_AVAX_JuniorTranche_RevertInvalidNativeTokenDeposit() external {
        console.log("ID: Pr_Dep_26");
        console.log("Reverts with error VE_INVALID_NATIVE_TOKEN_DEPOSIT if user deposits AVAX to non-wAVAX tranche");
        uint256 _value = 2e6;
        deal(address(user1), _value);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_NATIVE_TOKEN_DEPOSIT));
        user1.depositAvaxToJunior(_value, _value);
    }

    function testDeposit_AVAX_SeniorTranche_ProductContractConstantAVAXBalance() external {
        console.log("AVAX balance of product contract should be the same before and after AVAX deposit");
        uint256 contractProductAVAXBalanceBefore = user1.balanceOf();
        depositAVAXToSenior();
        uint256 contractProductAVAXBalanceAfter = user1.balanceOf();
        assertEq(contractProductAVAXBalanceBefore, contractProductAVAXBalanceAfter);
    }

    function testDeposit_AVAX_SeniorTranche_UserSubtractedAVAXBalance() external {
        console.log("AVAX balance of the user should be equal to balance before less _depositAmount");
        deal(address(user1), userBalance);
        uint256 userAVAXBalanceBefore = address(user1).balance;
        assertEq(userAVAXBalanceBefore, userBalance);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
        uint256 userAVAXBalanceAfter = address(user1).balance;
        assertEq(userAVAXBalanceBefore - _depositAmount, userAVAXBalanceAfter);
    }

    function testDeposit_AVAX_SeniorTranche_InvestorDepositedNative() external {
        console.log("investorDetails.depositedNative should be true");
        depositAVAXToSenior();
        DataTypes.Investor memory _investorDetails = user1.getInvestorDetails(DataTypes.Tranche.Senior);
        assertEq(_investorDetails.depositedNative, true);
    }

    function testDeposit_AVAX_SeniorTranche_EmitWeth9Deposit() external {
        console.log("Deposit with AVAX should emit Deposit event from WETH9 contract");
        deal(address(user1), userBalance);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        vm.expectEmit(false, true, true, true);
        emit Deposit(address(user1), _depositAmount);
        user1.depositAvaxToSenior(_depositAmount, _depositAmount);
    }

    function testDeposit_AVAX_WAVAX_SeniorTranche() external {
        console.log("Deposit with AVAX then wAVAX should keep track of user sum and depositedNative stays true");
        // step 1: deposit AVAX
        deal(address(user1), userBalance);
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        user1.depositAvaxToSenior(userBalance, userBalance);
        DataTypes.Investor memory _investorDetails = user1.getInvestorDetails(DataTypes.Tranche.Senior);
        assertEq(_investorDetails.depositedNative, true, "user deposited AVAX");
        uint256 _userSum1 = _investorDetails.userSums[_investorDetails.userSums.length - 1];
        assertEq(_userSum1, userBalance, "user sum recorded as 1 wei");

        // step 2: deposit wAVAX
        deal(address(wavax), address(user1), userBalance);
        user1.increaseAllowance(address(wavax), userBalance);
        user1.depositToSenior(userBalance);
        DataTypes.Investor memory _investorDetails2 = user1.getInvestorDetails(DataTypes.Tranche.Senior);
        uint256 _userSum2 = _investorDetails2.userSums[_investorDetails2.userSums.length - 1];
        assertEq(_userSum2, userBalance * 2, "user sum recorded as userBalance x 2");
        assertEq(address(user1).balance, 0, "AVAX transferred from user");
        assertEq(IERC20Metadata(address(wavax)).balanceOf(address(user1)), 0, "wAVAX transferred from user");
        assertEq(_investorDetails2.depositedNative, true, "user deposited AVAX is still true");
    }
}
