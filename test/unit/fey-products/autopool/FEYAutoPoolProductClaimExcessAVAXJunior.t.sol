// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IFEYFactory.sol";
import "../../../common/fey-products/autopool/WithdrawClaimExcessBaseTestSetup.sol";

contract FEYAutoPoolProductClaimExcessAVAXJunior_UnitTest is WithdrawClaimExcessBaseTestSetup {
    function onSetup() public virtual override {
        seniorTrancheIsWAVAX = false;
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testClaimExcess_ShouldTransferAVAXJunior() public {
        console.log("ID: Pr_CE_15");
        console.log("user should receive AVAX when calling claimExcess() and deposited AVAX into junior tranche wAVAX");

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(user1), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = true;
        _depositWarpInvestJunior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 balTokenJrProductPreClaim = wavax.balanceOf(address(sut));
        uint256 balTokenJrUserPreClaim = wavax.balanceOf(address(user1));

        user1.claimExcess(JUNIOR_TRANCHE);

        uint256 balTokenJrProductPostClaim = wavax.balanceOf(address(sut));
        uint256 balTokenJrUserPostClaim = wavax.balanceOf(address(user1));
        uint256 balAVAXUserPostClaim = address(user1).balance;
        uint256 balAVAXProductPostClaim = address(sut).balance;

        assertEq(balTokenJrProductPreClaim, depositValAVAX, "Product Jr tranche token bal pre claim");
        assertEq(balTokenJrUserPreClaim, 0, "User Jr tranche token bal pre claim");
        assertEq(balTokenJrProductPostClaim, 0, "Product Jr tranche token bal post claim");
        assertEq(balTokenJrUserPostClaim, 0, "User Jr tranche token bal post claim");
        assertEq(balAVAXUserPreDeposit, depositValAVAX, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostClaim, 0, "Product AVAX bal post claim");
        assertEq(balAVAXUserPreDeposit, balAVAXUserPostClaim, "User AVAX bal post claim");
    }

    function testClaimExcess_ShouldTransferWrappedAVAXJunior() public {
        console.log("ID: Pr_CE_17");
        console.log(
            "user should receive wrapped AVAX when calling claimExcess() and deposited wrapped AVAX into junior tranche wAVAX"
        );

        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        deal(address(wavax), address(user1), depositValAVAX);
        user1.increaseAllowance(address(wavax), depositValAVAX);
        uint256 balAVAXUserPreDeposit = address(user1).balance;
        bool withAVAX = false;
        _depositWarpInvestJunior(depositValAVAX, withAVAX);
        uint256 balAVAXUserPostDeposit = address(user1).balance;

        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));

        uint256 balTokenJrProductPreClaim = wavax.balanceOf(address(sut));
        uint256 balTokenJrUserPreClaim = wavax.balanceOf(address(user1));

        user1.claimExcess(JUNIOR_TRANCHE);

        uint256 balTokenJrProductPostClaim = wavax.balanceOf(address(sut));
        uint256 balTokenJrUserPostClaim = wavax.balanceOf(address(user1));
        uint256 balAVAXUserPostClaim = address(user1).balance;
        uint256 balAVAXProductPostClaim = address(sut).balance;

        assertEq(balTokenJrProductPreClaim, depositValAVAX, "Product Jr tranche token bal pre claim");
        assertEq(balTokenJrUserPreClaim, 0, "User Jr tranche token bal pre claim");
        assertEq(balTokenJrProductPostClaim, 0, "Product Jr tranche token bal post claim");
        assertEq(balTokenJrUserPostClaim, depositValAVAX, "User Jr tranche token bal post claim");
        assertEq(balAVAXUserPreDeposit, 0, "User AVAX bal pre deposit");
        assertEq(balAVAXUserPostDeposit, 0, "User AVAX bal post deposit");
        assertEq(balAVAXProductPostClaim, 0, "Product AVAX bal post claim");
        assertEq(balAVAXUserPostClaim, 0, "User AVAX bal post claim");
    }
}
