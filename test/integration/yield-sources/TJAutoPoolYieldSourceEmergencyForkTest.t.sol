pragma solidity 0.8.11;

import "../../common/yield-sources/YieldSourceBaseTestSetup.sol";

contract AutoPoolYieldSourceEmergency_IntegrationTest is YieldSourceBaseTestSetup {
    error BaseVault__NotInEmergencyMode();
    error BaseVault__ZeroShares();

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 34784870);
        autoPoolVault = autoPoolVault_AVAX_USDC;

        super.setUp();
    }

    function testEmergencyWithdrawFromFarm_Success() public {
        console.log("TJAP_YS_EWFF_1");
        console.log("yield source should receive AP tokens after emergencyWithdrawFromFarm is called");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        assertEq(autoPoolVault.balanceOf(address(sut)), 0, "balance == 0");
        vm.recordLogs();

        vm.prank(admin);
        sut.emergencyWithdrawFromFarm();
        assertGt(autoPoolVault.balanceOf(address(sut)), 0, "balance > 0");

        /// Should emit EmergencyWithdraw() method once
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 emergencyWithdrawEventCount;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("EmergencyWithdraw(address,uint256,uint256)")) {
                emergencyWithdrawEventCount++;
            }
        }
        assertEq(emergencyWithdrawEventCount, 1);
    }

    function testEmergencyWithdrawFromFarm_OnlyGovernance() public {
        console.log("TJAP_YS_EWFF_2");
        console.log("should be callable only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.emergencyWithdrawFromFarm();
    }

    function testEmergencyWithdrawFromAutoPool_ShouldRecieveTokenFromPool() public {
        console.log("TJAP_YS_EWFAP_1");
        console.log("yield source should receive tranche tokens after emergencyWithdrawFromAutoPool is called");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        assertEq(sut.tokenA().balanceOf(address(sut)), 0, "tokenA balance == 0");
        assertEq(sut.tokenB().balanceOf(address(sut)), 0, "tokenB balance == 0");

        vm.prank(admin);
        sut.emergencyWithdrawFromFarm();

        vm.prank(autoPoolFactory);
        autoPoolVault.setEmergencyMode();

        vm.prank(admin);
        sut.emergencyWithdrawFromAutoPool();

        assertGt(sut.tokenA().balanceOf(address(sut)), 0, "tokenA balance > 0");
        assertGt(sut.tokenB().balanceOf(address(sut)), 0, "tokenB balance > 0");
    }

    function testEmergencyWithdrawFromAutoPool_ShouldUpdateShares() public {
        console.log("TJAP_YS_EWFAP_5");
        console.log("totalAutopoolShareTokens should be set to 0");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        assertGt(sut.totalAutoPoolShareTokens(), 0, "totalAutoPoolShareTokens > 0");
        assertGt(sut.totalShares(), 0, "totalShares > 0");

        vm.prank(admin);
        sut.emergencyWithdrawFromFarm();

        vm.prank(autoPoolFactory);
        autoPoolVault.setEmergencyMode();

        vm.prank(admin);
        sut.emergencyWithdrawFromAutoPool();

        assertEq(sut.totalAutoPoolShareTokens(), 0, "totalAutoPoolShareTokens == 0");
        assertEq(sut.totalShares(), 0, "totalShares == 0");
    }

    function testEmergencyWithdrawFromAutoPool_Revert_NotInEmergencyMode() public {
        console.log("TJAP_YS_EWFAP_2");
        console.log(
            "emergencyWithdrawFromAutoPool should revert with error BaseVault__NotInEmergencyMode if Vault is not in emergency mode"
        );
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.prank(admin);
        sut.emergencyWithdrawFromFarm();

        vm.prank(admin);
        vm.expectRevert(abi.encodePacked(BaseVault__NotInEmergencyMode.selector));
        sut.emergencyWithdrawFromAutoPool();
    }

    function testEmergencyWithdrawFromAutoPool_Revert_ZeroShares() public {
        console.log("TJAP_YS_EWFAP_3");
        console.log(
            "yield source should revert with error BaseVault__ZeroShares if emergencyWithdrawFromFarm is not called before emergencyWithdrawFromAutoPool is called"
        );
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.prank(autoPoolFactory);
        autoPoolVault.setEmergencyMode();

        vm.startPrank(admin);
        vm.expectRevert(abi.encodePacked(BaseVault__ZeroShares.selector));
        sut.emergencyWithdrawFromAutoPool();
    }

    function testEmergencyWithdrawFromAutoPool_OnlyGovernance() public {
        console.log("TJAP_YS_EWFAP_4");
        console.log("should be callable only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.emergencyWithdrawFromAutoPool();
    }

    function testEmergencyWithdrawAndRescue_Success() public {
        console.log("TJAP_YS_EWAR_1");
        console.log("recipient should receive tranche tokens after emergencyWithdrawAndRescue is called");

        assertEq(sut.tokenA().balanceOf(admin), 0, "admin tokenA balance == 0");
        assertEq(sut.tokenB().balanceOf(admin), 0, "admin tokenB balance == 0");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.prank(autoPoolFactory);
        autoPoolVault.setEmergencyMode();

        vm.startPrank(admin);
        sut.emergencyWithdrawAndRescue(admin);

        assertGt(sut.tokenA().balanceOf(admin), 0, "admin tokenA balance > 0");
        assertGt(sut.tokenB().balanceOf(admin), 0, "admin tokenB balance > 0");
    }

    function testEmergencyWithdrawAndRescue_Revert_NotInEmergencyMode() public {
        console.log("TJAP_YS_EWAR_2");
        console.log(
            "emergencyWithdrawAndRescue should revert with error BaseVault__NotInEmergencyMode if Vault is not in emergency mode"
        );
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.prank(admin);
        vm.expectRevert(abi.encodePacked(BaseVault__NotInEmergencyMode.selector));
        sut.emergencyWithdrawAndRescue(admin);
    }

    function testEmergencyWithdrawAndRescue_OnlyGovernance() public {
        console.log("TJAP_YS_EWAR_3");
        console.log("should be callable only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.emergencyWithdrawAndRescue(admin);
    }

    function testEmergencyWithdrawAndRescue_WithoutFarm() public {
        console.log("should not emit EmergencyWithdraw events if there is no farm");

        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC"), 34470208);
        vm.selectFork(forkId);

        AutoPoolYieldSource sut2 =
        new AutoPoolYieldSource(autoPoolVaultWithoutFarm,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(usdt), address(usdc), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.prank(autoPoolFactory);
        autoPoolVaultWithoutFarm.setEmergencyMode();

        vm.recordLogs();

        vm.prank(admin);
        sut2.emergencyWithdrawAndRescue(admin);

        /// Should not emit EmergencyWithdraw() method
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 emergencyWithdrawEventCount;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("EmergencyWithdraw(address,uint256,uint256)")) {
                emergencyWithdrawEventCount++;
            }
        }
        assertEq(emergencyWithdrawEventCount, 0);
    }

    function testEmergencyRedeemQueuedWithdrawals_OnlyGovernance() public {
        console.log("should be callable only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.emergencyRedeemQueuedWithdrawal(5);
    }

    function testEmergencyRedeemQueuedWithdrawals_ShouldRedeemTokens() public {
        console.log("should redeemQueuedWithdrawals when called");
        IERC20Metadata tokenA;
        IERC20Metadata tokenB;

        tokenA = sut.tokenA();
        tokenB = sut.tokenB();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);

        vm.prank(mockProduct);
        sut.queueForRedemption();

        vm.prank(mockProduct2);
        sut.queueForRedemption();

        vm.prank(mockProduct3);
        sut.queueForRedemption();

        _simulateExecuteQueuedWithdrawls();

        uint256 tokenABalanceBefore = tokenA.balanceOf(address(sut));
        uint256 tokenBBalanceBefore = tokenB.balanceOf(address(sut));
        vm.startPrank(admin);
        sut.emergencyRedeemQueuedWithdrawal(autoPoolVault.getCurrentRound() - 1);
        vm.stopPrank();

        uint256 tokenABalanceAfter = tokenA.balanceOf(address(sut));
        uint256 tokenBBalanceAfter = tokenB.balanceOf(address(sut));

        assertGt(tokenABalanceAfter, tokenABalanceBefore, "tokenABalanceAfter > tokenBBalanceBefore");
        assertGt(tokenBBalanceAfter, tokenBBalanceBefore, "tokenBBalanceAfter > tokenBBalanceBefore");
    }
}
