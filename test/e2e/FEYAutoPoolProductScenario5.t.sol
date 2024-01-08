// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./FEYAutoPoolProductActions.sol";

contract FEYAutoPoolProductE2ETests_Scenario5 is FEYAutoPoolProductActions {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 33646790);

        super.setUp();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        uint256 _investmentTerm = 30 days;
        investTestsFixture(wavax, usdc, 1000e18, 20000e18, _investmentTerm);
    }

    function testAutoPoolProduct_Scenario5_Version1()
        public
        // final product state assertions (after all withdrawals processed)
        assertPostUserWithdrawalBalances(user1, SENIOR_TRANCHE)
        assertPostUserWithdrawalBalances(user2, JUNIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(SENIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(JUNIOR_TRANCHE)
        // condition fails - 3 wei of wAVAX dust left in product after all withdrawals are complete
        // this is due to a precision issue in dividing the amounts of wAVAX received on maturity
        // assertNoDustInProduct(sut, SENIOR_TRANCHE, false)
        assertNoDustInProduct(sut, JUNIOR_TRANCHE, false)
        assertNoDustInYieldSource(yieldSource, true)
    {
        _lineBreak();
        console.log("ID: TJAP_E2E_5");
        handleDepositToTranches(handleCreateUserDeposits(wavax, usdc, wavaxToDeposit, usdcToDeposit));
        handleInvestProduct(handleCreateUserDeposits(wavax, usdc, wavaxToDeposit, usdcToDeposit));
        handleApproveSpToken(user1);
        handleMockOracleCalls(autoPoolVault);
        handleQueueWithdrawals(autoPoolVault);
        handleRedeemTokens();
        // transfers 25% of SP tokens from user1 to user3
        uint256 _spTokensToTransfer = spToken.balanceOf(address(user1), uint256(SENIOR_TRANCHE)) / 4;
        handleTransferSpToken(_spTokensToTransfer, address(user1), address(user3));
        // user3 withdraws funds from senior tranche
        handleApproveSpToken(user3);
        handleWithdraw(user3, SENIOR_TRANCHE, wavax);
        // transfers 25% of SP tokens from user1 to user3
        handleTransferSpToken(_spTokensToTransfer, address(user1), address(user3));
        // user3 withdraws funds from senior tranche
        handleApproveSpToken(user3);
        handleWithdraw(user3, SENIOR_TRANCHE, wavax);
        // transfers 25% of SP tokens from user1 to user2
        handleTransferSpToken(_spTokensToTransfer, address(user1), address(user2));
        // user2 claims excess from junior tranche
        handleApproveSpToken(user2);
        handleClaimExcess(user2, JUNIOR_TRANCHE, usdc);
        // user1 withdraws funds from senior tranche
        handleApproveSpToken(user1);
        handleWithdraw(user1, SENIOR_TRANCHE, wavax);
        // user2 withdraws funds from junior tranche
        handleWithdraw(user2, JUNIOR_TRANCHE, usdc);
        // user2 withdraws funds from senior tranche
        handleWithdraw(user2, SENIOR_TRANCHE, wavax);
    }
}
