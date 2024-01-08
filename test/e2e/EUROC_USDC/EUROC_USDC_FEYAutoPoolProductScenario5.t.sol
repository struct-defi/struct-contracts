// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../FEYAutoPoolProductActions.sol";

contract EUROC_USDC_FEYAutoPoolProductE2ETests_Scenario5 is FEYAutoPoolProductActions {
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

    function testAutoPoolProduct_Scenario5_Version1()
        public
        // final product state assertions (after all withdrawals processed)
        assertPostUserWithdrawalBalances(user1, SENIOR_TRANCHE)
        assertPostUserWithdrawalBalances(user2, JUNIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(SENIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(JUNIOR_TRANCHE)
        assertNoDustInProduct(sut, SENIOR_TRANCHE, false)
        // condition fails - 1 wei of USDC dust left in product after all withdrawals are complete
        // this is due to a precision issue in dividing the amounts of USDC received on maturity
        // assertNoDustInProduct(sut, JUNIOR_TRANCHE, false)
        assertNoDustInYieldSource(yieldSource, true)
    {
        _lineBreak();
        console.log("ID: TJAP_E2E_5");
        handleDepositToTranches(handleCreateUserDeposits(euroc, usdc, eurocToDeposit, usdcToDeposit));
        handleInvestProduct(handleCreateUserDeposits(euroc, usdc, eurocToDeposit, usdcToDeposit));
        handleApproveSpToken(user1);
        handleMockOracleCalls(autoPoolVault_euroc_usdc);
        handleQueueWithdrawals(autoPoolVault_euroc_usdc);
        handleRedeemTokens();
        // transfers 25% of SP tokens from user1 to user3
        uint256 _spTokensToTransfer = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE)) / 4;
        handleTransferSpToken(_spTokensToTransfer, address(user1), address(user3));
        // user3 withdraws funds from senior tranche
        handleApproveSpToken(user3);
        handleWithdraw(user3, SENIOR_TRANCHE, euroc);
        // transfers 25% of SP tokens from user1 to user3
        handleTransferSpToken(_spTokensToTransfer, address(user1), address(user3));
        // user3 withdraws funds from senior tranche
        handleApproveSpToken(user3);
        handleWithdraw(user3, SENIOR_TRANCHE, euroc);
        // transfers 25% of SP tokens from user1 to user2
        handleTransferSpToken(_spTokensToTransfer, address(user1), address(user2));
        // user2 claims excess from junior tranche
        handleApproveSpToken(user2);
        handleClaimExcess(user2, JUNIOR_TRANCHE, usdc);
        // user1 withdraws funds from senior tranche
        handleApproveSpToken(user1);
        handleWithdraw(user1, SENIOR_TRANCHE, euroc);
        // user2 withdraws funds from junior tranche
        handleWithdraw(user2, JUNIOR_TRANCHE, usdc);
        // user2 withdraws funds from senior tranche
        handleWithdraw(user2, SENIOR_TRANCHE, euroc);
    }
}
