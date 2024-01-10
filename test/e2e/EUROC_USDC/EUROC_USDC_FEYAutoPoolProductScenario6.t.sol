// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../FEYAutoPoolProductActions.sol";

contract EUROC_USDC_FEYAutoPoolProductE2ETests_Scenario6 is FEYAutoPoolProductActions {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 36099013);

        super.setUp();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        uint256 _investmentTerm = 30 days;
        investTestsFixture(euroc, usdc, 9490e18, 10000e18, _investmentTerm);
    }

    function testAutoPoolProduct_Scenario6_Version1()
        public
        // final product state assertions (after all withdrawals processed)
        assertPostAllWithdrawalsSpTokenSupply(SENIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(JUNIOR_TRANCHE)
        assertNoDustInProduct(sut, SENIOR_TRANCHE, false)
        assertNoDustInProduct(sut, JUNIOR_TRANCHE, false)
        assertNoDustInYieldSource(yieldSource, true)
    {
        _lineBreak();
        console.log("ID: TJAP_E2E_6");
        handleDepositToTranches(handleCreateUserDeposits(euroc, usdc, eurocToDeposit, usdcToDeposit));
        handleForceUpdateStatusToWithdrawn();
        handleApproveSpToken(user2);
        handleClaimExcess(user2, JUNIOR_TRANCHE, usdc);
        handleApproveSpToken(user1);
        handleClaimExcess(user1, SENIOR_TRANCHE, euroc);
    }
}
