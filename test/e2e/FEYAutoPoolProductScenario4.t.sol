// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./FEYAutoPoolProductActions.sol";

contract FEYAutoPoolProductE2ETests_Scenario4 is FEYAutoPoolProductActions {
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

    function handleCreateUserDeposits() internal returns (UserDeposit[] memory _userDeposits) {
        _userDeposits = new UserDeposit[](5);
        _userDeposits[0] = UserDeposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax, true);
        _userDeposits[1] = UserDeposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax, false);
        _userDeposits[2] = UserDeposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax, true);
        _userDeposits[3] = UserDeposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax, false);
        _userDeposits[4] = UserDeposit(user2, usdcToDeposit * 8, JUNIOR_TRANCHE, usdc, false);
        return _userDeposits;
    }

    // Test multiple AVAX and wAVAX deposits:
    // 1.1 User1 deposits into senior tranche with AVAX
    // 1.2 User1 deposits into senior tranche with wAVAX
    // 1.3 User1 deposits into senior tranche with AVAX
    // 1.4 User1 deposits into senior tranche with wAVAX
    // 2. User2 deposits into junior tranche with USDC (2X amount in senior)
    // 3. At trancheStartTime, invest is called
    // 4. User2 calls claimExcess successfully
    // 5. At trancheEndTime, removeFundsFromLP is called
    // 6. Keeper calls redeemTokens
    // 7. User1 withdraws funds (receives funds in AVAX)
    // 8. User2 withdraws funds
    function testAutoPoolProduct_Scenario4_Version1()
        public
        // final product state assertions (after all withdrawals processed)
        assertPostAllWithdrawalsSpTokenSupply(SENIOR_TRANCHE)
        assertPostAllWithdrawalsSpTokenSupply(JUNIOR_TRANCHE)
        assertPostUserWithdrawalBalances(user1, SENIOR_TRANCHE)
        assertPostUserWithdrawalBalances(user2, JUNIOR_TRANCHE)
        assertNoDustInProduct(sut, SENIOR_TRANCHE, false)
        assertNoDustInProduct(sut, JUNIOR_TRANCHE, false)
        assertNoDustInYieldSource(yieldSource, true)
    {
        _lineBreak();
        console.log("ID: TJAP_E2E_4");
        handleDepositToTranches(handleCreateUserDeposits());
        handleInvestProduct(handleCreateUserDeposits());
        handleApproveSpToken(user1);
        handleApproveSpToken(user2);
        handleClaimExcess(user2, JUNIOR_TRANCHE, usdc);
        handleMockOracleCalls(autoPoolVault);
        handleQueueWithdrawals(autoPoolVault);
        handleRedeemTokens();
        handleWithdraw(user1, SENIOR_TRANCHE, wavax);
        handleWithdraw(user2, JUNIOR_TRANCHE, usdc);
    }
}
