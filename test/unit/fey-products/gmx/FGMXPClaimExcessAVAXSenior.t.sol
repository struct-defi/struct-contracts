// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IFEYFactory.sol";
import "../../../common/fey-products/gmx/WithdrawClaimExcessBaseTestSetup.sol";

contract FGMXPClaimExcessAVAXSeniorTest is WithdrawClaimExcessBaseTestSetup {
    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testClaimExcess_ShouldTransferAVAXSenior() public {
        console.log("ID: Pr_CE_14");
        console.log("user should receive AVAX when calling claimExcess() and deposited AVAX into senior tranche wAVAX");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(user1), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = true;
        _depositWarpInvestSenior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 balTokenSrProductPreClaim = wavax.balanceOf(address(sut));
        uint256 balTokenSrUserPreClaim = wavax.balanceOf(address(user1));

        user1.claimExcess(SENIOR_TRANCHE);

        uint256 balTokenSrProductPostClaim = wavax.balanceOf(address(sut));
        uint256 balTokenSrUserPostClaim = wavax.balanceOf(address(user1));
        uint256 balAVAXUserPostClaim = address(user1).balance;
        uint256 balAVAXProductPostClaim = address(sut).balance;

        assertEq(balTokenSrProductPreClaim, depositValAVAX, "Product Sr tranche token bal pre claim");
        assertEq(balTokenSrUserPreClaim, 0, "User Sr tranche token bal pre claim");
        assertEq(balTokenSrProductPostClaim, 0, "Product Sr tranche token bal post claim");
        assertEq(balTokenSrUserPostClaim, 0, "User Sr tranche token bal post claim");
        assertEq(balAVAXUserPreDeposit, depositValAVAX, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostClaim, 0, "Product AVAX bal post claim");
        assertEq(balAVAXUserPreDeposit, balAVAXUserPostClaim, "User AVAX bal post claim");
    }

    function testClaimExcess_ShouldTransferWrappedAVAXSenior() public {
        console.log("ID: Pr_CE_16");
        console.log(
            "user should receive wrapped AVAX when calling claimExcess() and deposited wrapped AVAX into senior tranche wAVAX"
        );

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), depositValAVAX);
        user1.increaseAllowance(address(wavax), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = false;
        _depositWarpInvestSenior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 balTokenSrProductPreClaim = wavax.balanceOf(address(sut));
        uint256 balTokenSrUserPreClaim = wavax.balanceOf(address(user1));

        user1.claimExcess(SENIOR_TRANCHE);

        uint256 balTokenSrProductPostClaim = wavax.balanceOf(address(sut));
        uint256 balTokenSrUserPostClaim = wavax.balanceOf(address(user1));
        uint256 balAVAXUserPostClaim = address(user1).balance;
        uint256 balAVAXProductPostClaim = address(sut).balance;

        assertEq(balTokenSrProductPreClaim, depositValAVAX, "Product Sr tranche token bal pre claim");
        assertEq(balTokenSrUserPreClaim, 0, "User Sr tranche token bal pre claim");
        assertEq(balTokenSrProductPostClaim, 0, "Product Sr tranche token bal post claim");
        assertEq(balTokenSrUserPostClaim, depositValAVAX, "User Sr tranche token bal post claim");
        assertEq(balAVAXUserPreDeposit, 0, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostClaim, 0, "Product AVAX bal post claim");
        assertEq(balAVAXUserPostClaim, 0, "User AVAX bal post claim");
    }
}
