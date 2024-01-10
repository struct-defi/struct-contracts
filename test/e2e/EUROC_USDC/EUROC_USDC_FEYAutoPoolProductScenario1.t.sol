// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@external/traderjoe/IStrategy.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../FEYAutoPoolProductActions.sol";

contract EUROC_USDC_FEYAutoPoolProductE2ETests_Scenario1 is FEYAutoPoolProductActions {
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

    // Tests the happy path with srToken as EUROC, and jrToken as USDC:
    // 1. User1 deposits into senior tranche with EUROC
    // 2. User2 deposits into junior tranche with USDC (2X amount in senior)
    // 3. At trancheStartTime, invest is called
    // 4. User2 calls claimExcess successfully
    // 5. At trancheEndTime, removeFundsFromLP is called
    // 6. Keeper calls redeemTokens
    // 7. User1 withdraws funds
    // 8. User2 withdraws funds
    function testAutoPoolProduct_Scenario1_Version1()
        public
        // final product state assertions (after all withdrawals processed)
        assertPostUserWithdrawalBalances(user1, SENIOR_TRANCHE)
        assertPostUserWithdrawalBalances(user2, JUNIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(SENIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(JUNIOR_TRANCHE)
        assertNoDustInProduct(sut, SENIOR_TRANCHE, false)
        assertNoDustInProduct(sut, JUNIOR_TRANCHE, false)
        assertNoDustInYieldSource(yieldSource, true)
    {
        _lineBreak();
        console.log("ID: TJAP_E2E_1");
        handleDepositToTranches(handleCreateUserDeposits(euroc, usdc, eurocToDeposit, usdcToDeposit));
        handleInvestProduct(handleCreateUserDeposits(euroc, usdc, eurocToDeposit, usdcToDeposit));
        handleApproveSpToken(user1);
        handleApproveSpToken(user2);
        handleClaimExcess(user2, JUNIOR_TRANCHE, usdc);
        handleMockOracleCalls(autoPoolVault_euroc_usdc);
        handleQueueWithdrawals(autoPoolVault_euroc_usdc);
        handleRedeemTokens();
        handleWithdraw(user1, SENIOR_TRANCHE, euroc);
        handleWithdraw(user2, JUNIOR_TRANCHE, usdc);
    }
}
