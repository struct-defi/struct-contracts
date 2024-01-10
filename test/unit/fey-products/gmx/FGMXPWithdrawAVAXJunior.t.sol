// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IFEYFactory.sol";
import "../../../common/fey-products/gmx/WithdrawClaimExcessBaseTestSetup.sol";

contract FGMXPWithdrawAVAXJunior_UnitTest is WithdrawClaimExcessBaseTestSetup {
    function onSetup() public virtual override {
        seniorTrancheIsWAVAX = false;
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testWithdraw_ShouldTransferAVAXJunior() public {
        console.log("ID: Pr_Wi_8");
        console.log("user should receive AVAX when calling withdraw() and deposited AVAX into junior tranche wAVAX");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(user1), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = true;
        _depositWarpInvestJunior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        setProductStateForWithdrawal(JUNIOR_TRANCHE);

        uint256 balTokenJrProductPreWithdraw = wavax.balanceOf(address(sut));
        uint256 balTokenJrUserPreWithdraw = wavax.balanceOf(address(user1));

        user1.withdraw(JUNIOR_TRANCHE);

        (
            uint256 balTokenJrProductPostWithdraw,
            uint256 balTokenJrUserPostWithdraw,
            uint256 balAVAXUserPostWithdraw,
            uint256 balAVAXProductPostWithdraw
        ) = getProductAndUserBalancesPostMUT();

        assertEq(balTokenJrProductPreWithdraw, depositValAVAX, "Product Jr tranche token bal pre withdraw");
        assertEq(balTokenJrUserPreWithdraw, 0, "User Jr tranche token bal pre withdraw");
        assertEq(balTokenJrProductPostWithdraw, 0, "Product Jr tranche token bal post withdraw");
        assertEq(balTokenJrUserPostWithdraw, 0, "User Jr tranche token bal post withdraw");
        assertEq(balAVAXUserPreDeposit, depositValAVAX, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostWithdraw, 0, "Product AVAX bal post withdraw");
        assertEq(balAVAXUserPreDeposit, balAVAXUserPostWithdraw, "User AVAX bal post withdraw");
        assertEq(balAVAXUserPostWithdraw, depositValAVAX, "User AVAX bal post withdraw eq deposit val");
    }

    function testWithdraw_ShouldTransferWrappedAVAXJunior() public {
        console.log("ID: Pr_Wi_10");
        console.log(
            "user should receive wrapped AVAX when calling withdraw() and deposited wrapped AVAX into junior tranche wAVAX"
        );

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), depositValAVAX);
        user1.increaseAllowance(address(wavax), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = false;
        _depositWarpInvestJunior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        setProductStateForWithdrawal(JUNIOR_TRANCHE);

        uint256 balTokenJrProductPreWithdraw = wavax.balanceOf(address(sut));
        uint256 balTokenJrUserPreWithdraw = wavax.balanceOf(address(user1));

        user1.withdraw(JUNIOR_TRANCHE);

        (
            uint256 balTokenJrProductPostWithdraw,
            uint256 balTokenJrUserPostWithdraw,
            uint256 balAVAXUserPostWithdraw,
            uint256 balAVAXProductPostWithdraw
        ) = getProductAndUserBalancesPostMUT();

        assertEq(balTokenJrProductPreWithdraw, depositValAVAX, "Product Jr tranche token bal pre withdraw");
        assertEq(balTokenJrUserPreWithdraw, 0, "User Jr tranche token bal pre withdraw");
        assertEq(balTokenJrProductPostWithdraw, 0, "Product Jr tranche token bal post withdraw");
        assertEq(balTokenJrUserPostWithdraw, depositValAVAX, "User Jr tranche token bal post withdraw");
        assertEq(balAVAXUserPreDeposit, 0, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostWithdraw, 0, "Product AVAX bal post withdraw");
        assertEq(balAVAXUserPostWithdraw, 0, "User AVAX bal post withdraw");
    }
}
