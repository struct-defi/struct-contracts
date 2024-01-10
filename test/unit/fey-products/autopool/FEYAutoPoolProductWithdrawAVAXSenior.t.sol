// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IFEYFactory.sol";
import "../../../common/fey-products/autopool/WithdrawClaimExcessBaseTestSetup.sol";

contract FEYAutoPoolProductWithdrawAVAXSenior_UnitTest is WithdrawClaimExcessBaseTestSetup {
    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testWithdraw_ShouldTransferAVAXSenior() public {
        console.log("ID: Pr_Wi_7");
        console.log("user should receive AVAX when calling withdraw() and deposited AVAX into senior tranche wAVAX");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(user1), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = true;
        _depositWarpInvestSenior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        setProductStateForWithdrawal(SENIOR_TRANCHE);

        uint256 balTokenSrProductPreWithdraw = wavax.balanceOf(address(sut));
        uint256 balTokenSrUserPreWithdraw = wavax.balanceOf(address(user1));

        user1.withdraw(SENIOR_TRANCHE);

        (
            uint256 balTokenSrProductPostWithdraw,
            uint256 balTokenSrUserPostWithdraw,
            uint256 balAVAXUserPostWithdraw,
            uint256 balAVAXProductPostWithdraw
        ) = getProductAndUserBalancesPostMUT();

        assertEq(balTokenSrProductPreWithdraw, depositValAVAX, "Product Sr tranche token bal pre withdraw");
        assertEq(balTokenSrUserPreWithdraw, 0, "User Sr tranche token bal pre withdraw");
        assertEq(balTokenSrProductPostWithdraw, 0, "Product Sr tranche token bal post withdraw");
        assertEq(balTokenSrUserPostWithdraw, 0, "User Sr tranche token bal post withdraw");
        assertEq(balAVAXUserPreDeposit, depositValAVAX, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostWithdraw, 0, "Product AVAX bal post withdraw");
        assertEq(balAVAXUserPreDeposit, balAVAXUserPostWithdraw, "User AVAX bal post withdraw");
        assertEq(balAVAXUserPostWithdraw, depositValAVAX, "User AVAX bal post withdraw eq deposit val");
    }

    function testWithdraw_ShouldTransferWrappedAVAXSenior() public {
        console.log("ID: Pr_Wi_9");
        console.log(
            "user should receive wrapped AVAX when calling withdraw() and deposited wrapped AVAX into senior tranche wAVAX"
        );

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), depositValAVAX);
        user1.increaseAllowance(address(wavax), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = false;
        _depositWarpInvestSenior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        setProductStateForWithdrawal(SENIOR_TRANCHE);

        uint256 balTokenSrProductPreWithdraw = wavax.balanceOf(address(sut));
        uint256 balTokenSrUserPreWithdraw = wavax.balanceOf(address(user1));

        user1.withdraw(SENIOR_TRANCHE);

        (
            uint256 balTokenSrProductPostWithdraw,
            uint256 balTokenSrUserPostWithdraw,
            uint256 balAVAXUserPostWithdraw,
            uint256 balAVAXProductPostWithdraw
        ) = getProductAndUserBalancesPostMUT();

        assertEq(balTokenSrProductPreWithdraw, depositValAVAX, "Product Sr tranche token bal pre withdraw");
        assertEq(balTokenSrUserPreWithdraw, 0, "User Sr tranche token bal pre withdraw");
        assertEq(balTokenSrProductPostWithdraw, 0, "Product Sr tranche token bal post withdraw");
        assertEq(balTokenSrUserPostWithdraw, depositValAVAX, "User Sr tranche token bal post withdraw");
        assertEq(balAVAXUserPreDeposit, 0, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostWithdraw, 0, "Product AVAX bal post withdraw");
        assertEq(balAVAXUserPostWithdraw, 0, "User AVAX bal post withdraw");
    }
}
