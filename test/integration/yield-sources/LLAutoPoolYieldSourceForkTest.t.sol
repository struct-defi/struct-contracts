pragma solidity 0.8.11;

import "../../common/yield-sources/YieldSourceBaseTestSetup.sol";
import "@core/yield-sources/LLAutoPoolYieldSource.sol";

contract LLAutoPoolYieldSource_IntegrationTest is YieldSourceBaseTestSetup {
    IERC20Metadata tokenA;
    IERC20Metadata tokenB;
    LLAutoPoolYieldSource llSut;

    IAutoPoolVault internal constant USDC_EURC_VAULT = IAutoPoolVault(0x052AF5B8aC73082D8c4C8202bB21F4531A51DC73);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 36974488);
        autoPoolVault = USDC_EURC_VAULT;

        super.setUp();

        llSut = new LLAutoPoolYieldSource(autoPoolVault,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));
        tokenA = llSut.tokenA();
        tokenB = llSut.tokenB();
    }

    function testConstructorLLAP_ShouldInitializeWithCorrectTokens() public {
        assertEq(address(llSut.tokenA()), address(autoPoolVault.getTokenX()));
        assertEq(address(llSut.tokenB()), address(autoPoolVault.getTokenY()));
    }

    function testSupplyTokensLLAP_ShouldUpdateTotalShares() public {
        console.log("should update the total shares and it should be equal to sum of product shares");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);

        assertEq(
            llSut.totalShares(),
            llSut.productAPTShare(mockProduct) + llSut.productAPTShare(mockProduct2)
                + llSut.productAPTShare(mockProduct3)
        );
    }

    function testSupplyTokensLLAP_ShouldUpdateTotalAutoPoolShareTokens() public {
        uint256 atpShareTokens = llSut.totalAutoPoolShareTokens();
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        assertGt(llSut.totalAutoPoolShareTokens(), atpShareTokens);

        atpShareTokens = llSut.totalAutoPoolShareTokens();

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);
        assertGt(llSut.totalAutoPoolShareTokens(), atpShareTokens);
        atpShareTokens = llSut.totalAutoPoolShareTokens();
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);
        assertGt(llSut.totalAutoPoolShareTokens(), atpShareTokens);
    }

    function testQueueForRedemptionLLAP_ShouldUpdateTotalShares() public {
        console.log("should subtract the totalShares with the product shares");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        uint256 product1Shares = llSut.productAPTShare(mockProduct);
        uint256 totalSharesBefore = llSut.totalShares();

        vm.prank(mockProduct);
        llSut.queueForRedemption();
        uint256 totalSharesAfter = llSut.totalShares();

        assertEq(totalSharesAfter, totalSharesBefore - product1Shares);

        vm.prank(mockProduct2);
        llSut.queueForRedemption();
        assertEq(llSut.totalShares(), 0);
    }

    function testQueueForRedemptionLLAP_ShouldUpdateProductShares() public {
        console.log("should set the productShares to 0 after redemption");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        uint256 product1Shares = llSut.productAPTShare(mockProduct);
        uint256 product2Shares = llSut.productAPTShare(mockProduct);

        // Make sure that the product shares are non-zero before redemption
        assertGt(product1Shares, 0);
        assertGt(product2Shares, 0);

        vm.prank(mockProduct);
        llSut.queueForRedemption();
        product1Shares = llSut.productAPTShare(mockProduct);
        assertEq(product1Shares, 0);

        vm.prank(mockProduct2);
        llSut.queueForRedemption();

        product2Shares = llSut.productAPTShare(mockProduct);
        assertEq(product2Shares, 0);
    }

    function testQueueForRedemptionLLAP_ShouldUpdateTotalLLAPTokenShares() public {
        console.log("should update the atpShareTokensTotal value");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        vm.prank(mockProduct);
        llSut.queueForRedemption();
        uint256 _apShareTokenTotal = llSut.totalAutoPoolShareTokens();
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(3, address(llSut));
        uint256 _apShareTokenBalance = _userInfo.amount;
        assertGt(_apShareTokenTotal, 0, "1: _apShareTokenTotal==0");
        assertEq(_apShareTokenTotal, _apShareTokenBalance, "_apShareTokenTotal==_apShareTokenBalance");

        vm.prank(mockProduct2);
        llSut.queueForRedemption();
        _apShareTokenTotal = llSut.totalAutoPoolShareTokens();

        assertEq(_apShareTokenTotal, 0, "2: _apShareTokenTotal==0");
    }

    function testQueueForRedemptionLLAP_ShouldEmitRedemptionQueuedEvent() public {
        console.log("should emit `RedemptionQueued` Event with correct product address and roundId");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        vm.startPrank(mockProduct);
        vm.expectEmit(true, true, true, true);
        emit RedemptionQueued(mockProduct, autoPoolVault.getCurrentRound());
        llSut.queueForRedemption();
        vm.stopPrank();

        vm.startPrank(mockProduct2);
        vm.expectEmit(true, true, true, true);
        emit RedemptionQueued(mockProduct2, autoPoolVault.getCurrentRound());
        llSut.queueForRedemption();
        vm.stopPrank();
    }

    function testQueueForRedemptionLLAP_ShouldRevertWhenNoShares() public {
        console.log("should revert when tried to redeem when there are no shares");

        // Redeeming without supplying should revert
        vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.NoShares.selector));
        vm.prank(mockProduct);
        llSut.queueForRedemption();

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.prank(mockProduct);
        llSut.queueForRedemption();

        // Should be able to redeem only once
        vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.NoShares.selector));
        vm.prank(mockProduct);
        llSut.queueForRedemption();
    }

    function testRedeemTokensLLAP_ShouldUpdateLastProcessedRound() public {
        console.log("should update the `nextRoundIndexToBeProcessed` after every execution");
        vm.mockCall(
            address(mockProduct),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        vm.mockCall(
            address(mockProduct2),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockProduct3),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.prank(mockProduct);
        llSut.queueForRedemption();
        assertEq(llSut.nextRoundIndexToBeProcessed(), 0);
        _simulateExecuteQueuedWithdrawls();

        llSut.redeemTokens();
        assertEq(llSut.nextRoundIndexToBeProcessed(), 1);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);
        vm.prank(mockProduct2);
        llSut.queueForRedemption();

        vm.prank(mockProduct3);
        llSut.queueForRedemption();

        _simulateExecuteQueuedWithdrawls();

        llSut.redeemTokens();
        assertEq(llSut.nextRoundIndexToBeProcessed(), 2);
    }

    function testQueueRedemptionLLAP_ShouldUpdateRoundInfo_totalShares() public {
        console.log("should update the `totalShares` value for the current round");
        vm.mockCall(
            address(mockProduct),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        vm.mockCall(
            address(mockProduct2),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockProduct3),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);

        uint256 _productShares = llSut.productAPTShare(address(mockProduct));
        vm.prank(mockProduct);
        llSut.queueForRedemption();
        DataTypes.Round memory _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalShares, 0);
        assertEq(_roundInfo.totalShares, _productShares);

        _simulateExecuteQueuedWithdrawls();

        llSut.redeemTokens();

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);

        uint256 _product2Shares = llSut.productAPTShare(address(mockProduct2));
        uint256 _product3Shares = llSut.productAPTShare(address(mockProduct3));

        vm.prank(mockProduct2);
        llSut.queueForRedemption();

        vm.prank(mockProduct3);
        llSut.queueForRedemption();

        _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalShares, 0);
        assertEq(_roundInfo.totalShares, _product2Shares + _product3Shares);
    }

    function testQueueRedemptionLLAP_ShouldUpdateRoundInfo_totalAutoPoolTokens() public {
        console.log("should update the `totalAutoPoolTokens` value for the current round");
        vm.mockCall(
            address(mockProduct),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        vm.mockCall(
            address(mockProduct2),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockProduct3),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);

        uint256 _autoPoolShareTokensBalanceBefore = llSut.totalAutoPoolShareTokens();
        vm.prank(mockProduct);
        llSut.queueForRedemption();
        uint256 _autoPoolShareTokensBalanceAfter = llSut.totalAutoPoolShareTokens();

        DataTypes.Round memory _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalAutoPoolTokens, 0);
        assertEq(_roundInfo.totalAutoPoolTokens, _autoPoolShareTokensBalanceBefore - _autoPoolShareTokensBalanceAfter);

        _simulateExecuteQueuedWithdrawls();

        llSut.redeemTokens();

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);

        _autoPoolShareTokensBalanceBefore = llSut.totalAutoPoolShareTokens();

        vm.prank(mockProduct2);
        llSut.queueForRedemption();

        vm.prank(mockProduct3);
        llSut.queueForRedemption();
        _autoPoolShareTokensBalanceAfter = llSut.totalAutoPoolShareTokens();
        _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalAutoPoolTokens, 0);
        assertEq(_roundInfo.totalAutoPoolTokens, _autoPoolShareTokensBalanceBefore - _autoPoolShareTokensBalanceAfter);
    }

    function testQueueRedemptionLLAP_ShouldUpdateRoundInfo_ProductsAndShares() public {
        console.log("should update the `products` and `shares` array for the current round");
        vm.mockCall(
            address(mockProduct),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        vm.mockCall(
            address(mockProduct2),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockProduct3),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        uint256 _productShares = llSut.productAPTShare(address(mockProduct));

        vm.prank(mockProduct);
        llSut.queueForRedemption();

        uint256 _currentRound = autoPoolVault.getCurrentRound();
        DataTypes.Round memory _roundInfo = llSut.getRoundInfo(_currentRound);

        assertEq(_roundInfo.products.length, 1);
        assertEq(_roundInfo.shares.length, 1);

        assertEq(_roundInfo.products[0], mockProduct);
        assertEq(_roundInfo.shares[0], _productShares);

        _simulateExecuteQueuedWithdrawls();

        llSut.redeemTokens();

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);

        uint256 _product2Shares = llSut.productAPTShare(address(mockProduct2));
        uint256 _product3Shares = llSut.productAPTShare(address(mockProduct3));

        vm.prank(mockProduct2);
        llSut.queueForRedemption();

        vm.prank(mockProduct3);
        llSut.queueForRedemption();

        _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertEq(_roundInfo.products.length, 2);
        assertEq(_roundInfo.shares.length, 2);

        assertEq(_roundInfo.products[0], mockProduct2);
        assertEq(_roundInfo.shares[0], _product2Shares);

        assertEq(_roundInfo.products[1], mockProduct3);
        assertEq(_roundInfo.shares[1], _product3Shares);
    }

    function testRedeemTokensLLAP_ShouldUpdateRoundInfo_redeemed() public {
        console.log("should update the `redeemed` flag after every execution");
        vm.mockCall(
            address(mockProduct),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        vm.mockCall(
            address(mockProduct2),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockProduct3),
            abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
            abi.encode(true)
        );

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.prank(mockProduct);
        llSut.queueForRedemption();
        _simulateExecuteQueuedWithdrawls();
        DataTypes.Round memory _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound() - 1);
        assertEq(_roundInfo.redeemed, false);

        llSut.redeemTokens();
        _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound() - 1);

        assertEq(_roundInfo.redeemed, true);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct3);
        vm.prank(mockProduct2);
        llSut.queueForRedemption();

        vm.prank(mockProduct3);
        llSut.queueForRedemption();

        _simulateExecuteQueuedWithdrawls();

        llSut.redeemTokens();
        _roundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound() - 1);

        assertEq(_roundInfo.redeemed, true);
    }

    function testQueueForRedemptionLLAP_ShouldRevertIfRoundOccupied() public {
        console.log("should revert if `RoundOccupied()` if current round is full");

        address[] memory products = new address[](10);
        for (uint256 i; i < 10; i++) {
            address _product = getNextAddress();
            vm.prank(mockFactory);
            gac.grantRole(PRODUCT, _product);
            products[i] = _product;
            vm.mockCall(
                address(_product),
                abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
                abi.encode(true)
            );
        }

        /// All the products deposit and then queues for redemption
        for (uint256 i; i < 5; i++) {
            _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), products[i]);
            vm.prank(products[i]);
            llSut.queueForRedemption();
        }

        DataTypes.Round memory _currentRoundInfo = llSut.getRoundInfo(autoPoolVault.getCurrentRound());

        assert(
            _currentRoundInfo.products.length == _currentRoundInfo.shares.length
                && _currentRoundInfo.products.length == 5 // since max iteration = 5
        );

        /// Assert that first 5 products are in current round and the remaining 5 products are queues for the next round
        for (uint256 i; i < 5; i++) {
            assertEq(_currentRoundInfo.products[i], products[i]);
        }
        uint256 tokenABalanceBefore = tokenA.balanceOf(address(llSut));
        uint256 tokenBBalanceBefore = tokenB.balanceOf(address(llSut));
        for (uint256 i = 5; i < 10; i++) {
            _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), products[i]);
            vm.startPrank(products[i]);

            vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.RoundOccupied.selector));
            llSut.queueForRedemption();

            vm.stopPrank();
        }
        uint256 tokenABalanceAfter = tokenA.balanceOf(address(llSut));
        uint256 tokenBBalanceAfter = tokenB.balanceOf(address(llSut));

        assertEq(tokenABalanceBefore, tokenABalanceAfter);
        assertEq(tokenBBalanceBefore, tokenBBalanceAfter);
    }

    function testRedeemTokensLLAP_ShouldReturnIfMaxIterationsHit() public {
        console.log("should exit execution if max iterations is hit");

        address[] memory products = new address[](10);
        for (uint256 i; i < 10; i++) {
            address _product = getNextAddress();
            vm.prank(mockFactory);
            gac.grantRole(PRODUCT, _product);
            products[i] = _product;
            vm.mockCall(
                address(_product),
                abi.encodeWithSelector(IAutoPoolFEYProduct.processRedemption.selector),
                abi.encode(true)
            );
        }

        uint256 currentRound = autoPoolVault.getCurrentRound();

        /// All the products deposit and then queues for redemption
        for (uint256 i; i < 10; i++) {
            if (i == 5) _simulateExecuteQueuedWithdrawls(); // Round Id 73

            _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), products[i]);
            vm.prank(products[i]);
            llSut.queueForRedemption();
        }
        // Round Id 74
        _simulateExecuteQueuedWithdrawls();
        /// Now the current round Id is 75, the rounds 73 and 74 should be processed on this call.
        llSut.redeemTokens();

        DataTypes.Round memory _currentRoundInfo = llSut.getRoundInfo(currentRound);
        DataTypes.Round memory _nextRoundInfo = llSut.getRoundInfo(currentRound + 1);

        /// Since the round 73 has 10 products already, only those products will be processed and the next round 74 will be skipped since the max iterations=10
        assertEq(_currentRoundInfo.redeemed, true, "only current round is executed");
        assertEq(_nextRoundInfo.redeemed, false, "next round is skipped");

        /// Still, the latest roundId is 75, but last processed roundId is 73. So this time round 74 should be processed.
        llSut.redeemTokens();
        _nextRoundInfo = llSut.getRoundInfo(currentRound + 1);
        assertEq(_nextRoundInfo.redeemed, true, "next round is processed");
    }

    function testRedeemTokensLLAP_ShouldRevertIfInvalidCaller() public {
        console.log("should revert with error code `29` if caller is not KEEPER");

        vm.startPrank(mockProduct);
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.redeemTokens();
    }
    /// GAC ////

    function testSupplyTokensLLAP_RevertWhenLocalPaused() public {
        console.log("should revert when the contract is paused locally");

        vm.prank(pauser);
        llSut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        llSut.supplyTokens(120, 120);
    }

    function testSupplyTokensLLAP_RevertWhenGlobalPaused() public {
        console.log("should revert when the contract is paused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        llSut.supplyTokens(120, 120);
    }

    function testSupplyTokensLLAP_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused locally");

        vm.prank(pauser);
        llSut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        llSut.supplyTokens(120, 120);

        vm.prank(pauser);
        llSut.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.supplyTokens(120, 120);
    }

    function testSupplyTokensLLAP_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        llSut.supplyTokens(120, 120);

        vm.prank(pauser);
        gac.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.supplyTokens(120, 120);
    }

    function testQueueForRedemptionLLAP_RevertWhenLocalPaused() public {
        console.log("should revert when the contract is paused locally");

        vm.prank(pauser);
        llSut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        llSut.queueForRedemption();
    }

    function testQueueForRedemptionLLAP_RevertWhenGlobalPaused() public {
        console.log("should revert when the contract is paused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        llSut.queueForRedemption();
    }

    function testQueueForRedemptionLLAP_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused locally");

        vm.prank(pauser);
        llSut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        llSut.queueForRedemption();

        vm.prank(pauser);
        llSut.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.queueForRedemption();
    }

    function testQueueForRedemptionLLAP_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        llSut.queueForRedemption();

        vm.prank(pauser);
        gac.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.queueForRedemption();
    }

    function testSetMaxIterations_ShouldUpdateMaxIterations() public {
        console.log("should update the maxIterations value");

        assertEq(llSut.maxIterations(), 5);

        vm.prank(admin);
        llSut.setMaxIterations(15);

        assertEq(llSut.maxIterations(), 15);
    }

    function testSetMaxIterations_ShouldEmitMaxIterationsUpdatedEvent() public {
        console.log("should emit `MaxIterationsUpdated` event");

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(llSut));
        emit MaxIterationsUpdated(15);
        llSut.setMaxIterations(15);
    }

    function testSetMaxIterations_ShouldRevert_IfInputZero() public {
        console.log("should revert if 0 is passed as input");

        vm.prank(admin);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ZERO_VALUE));
        llSut.setMaxIterations(0);
    }

    function testSetMaxIterations_ShouldRevert_IfCalledFromNonGovernanceAccount() public {
        console.log("should revert the caller doesn't have `GOVERNANCE` role");

        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.setMaxIterations(10);
    }

    function testRecompoundRewardsLLAP_ShouldEmitTokensFarmedEvent() public {
        console.log("should emit `TokensFarmed` event");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(3, address(llSut));
        uint256 _apShareTokenBalanceBefore = _userInfo.amount;
        _mockLatestRoundData();
        vm.recordLogs();
        llSut.recompoundRewards();

        _userInfo = aptFarm.userInfo(3, address(llSut));
        uint256 _apShareTokenBalanceAfter = _userInfo.amount;

        uint256 _tokensStaked = _apShareTokenBalanceAfter - _apShareTokenBalanceBefore;

        Vm.Log[] memory entries = vm.getRecordedLogs();

        /// Subtract 2, since the last event is RecompoundRewards() and last before event is TokensFarmed()
        assertEq(entries[entries.length - 2].topics[0], keccak256("TokensFarmed(uint256)"));
        assertEq(abi.decode(entries[entries.length - 2].data, (uint256)), _tokensStaked);
    }

    function testRecompoundRewardsLLAP_ShouldEmitRewardsRecompoundedEvent() public {
        console.log("should emit `RewardsRecompounded` event");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        _mockLatestRoundData();
        vm.recordLogs();
        llSut.recompoundRewards();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(
            entries[entries.length - 1].topics[0], keccak256("RewardsRecompounded(uint256,uint256,uint256,uint256)")
        );
    }

    function testRecompoundRewardsLLAP_WithDualReward_Native() public {
        console.log("should recompound both rewards");

        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        _mockLatestRoundData();
        vm.recordLogs();
        llSut.recompoundRewards();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(
            entries[entries.length - 1].topics[0], keccak256("RewardsRecompounded(uint256,uint256,uint256,uint256)")
        );
        (uint256 _rewards1, uint256 _rewards2, uint256 _harvestedTokenA, uint256 _harvestedTokenB) =
            abi.decode(entries[entries.length - 1].data, (uint256, uint256, uint256, uint256));
        assertGt(_rewards1, 0, "_rewards1 > 0");
        assertGt(_rewards2, 0, "_rewards2 > 0");

        uint256 _harvestedTokenAValue = _getPrice(address(tokenA)) * _harvestedTokenA / 1e18;
        uint256 _harvestedTokenBValue = _getPrice(address(tokenB)) * (_harvestedTokenB * 1e12) / 1e18;
        uint256 _rewards1Value = _getPrice(address(joe)) * _rewards1 / 1e18;
        uint256 _rewards2Value = _getPrice(address(wavax)) * _rewards2 / 1e18;

        /// Reward1 + Reward2 value should be (almost) equal to harvestedTokenValues A and B combined.
        assertApproxEqRel(_harvestedTokenAValue + _harvestedTokenBValue, _rewards1Value + _rewards2Value, 0.05e18); // approx equal 5%
    }

    function testRecompoundRewardsLLAP_WithoutFarm() public {
        console.log("should not revert nor emit RewardsRecompounded and TokensFarmed events if there is no farm");

        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC"), 34470208);
        vm.selectFork(forkId);

        AutoPoolYieldSource sut2 =
        new AutoPoolYieldSource(autoPoolVaultWithoutFarm,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(usdt), address(tokenB), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        vm.recordLogs();

        // Should not revert and should do nothing
        sut2.recompoundRewards();

        /// Should not emit RewardsRecompounded() method
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 rewardsRecompoundedEventCount;
        uint256 tokensFarmedEventCount;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RewardsRecompounded(uint256,uint256,uint256,uint256)")) {
                rewardsRecompoundedEventCount++;
            }
            if (entries[i].topics[0] == keccak256("TokensFarmed(uint256)")) {
                tokensFarmedEventCount++;
            }
        }
        assertEq(rewardsRecompoundedEventCount, 0);
        assertEq(tokensFarmedEventCount, 0);
    }

    function testQueueForRedemptionLLAP_WithoutFarm() public {
        console.log("should not revert nor emit RewardsRecompounded and TokensFarmed events if there is no farm");

        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC"), 34470208);
        vm.selectFork(forkId);

        AutoPoolYieldSource sut2 =
        new AutoPoolYieldSource(autoPoolVaultWithoutFarm,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(usdt), address(tokenB), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        vm.recordLogs();

        uint256 _productSharesBefore = sut2.productAPTShare(address(mockProduct));

        // Should not revert and should do nothing
        vm.prank(mockProduct);
        sut2.queueForRedemption();

        uint256 _productSharesAfter = sut2.productAPTShare(address(mockProduct));

        /// Should not emit RewardsRecompounded() method
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 rewardsRecompoundedEventCount;
        uint256 tokensFarmedEventCount;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RewardsRecompounded(uint256,uint256,uint256,uint256)")) {
                rewardsRecompoundedEventCount++;
            }
            if (entries[i].topics[0] == keccak256("TokensFarmed(uint256)")) {
                tokensFarmedEventCount++;
            }
        }
        assertEq(rewardsRecompoundedEventCount, 0);
        assertEq(tokensFarmedEventCount, 0);

        assertGt(_productSharesBefore, 0);
        assertEq(_productSharesAfter, 0);
    }

    function testHarvestRewardsLLAP_OnlyGovernance() public {
        console.log("harvest rewards should be called only by GOVERNANCE");
        _simulateSupply(address(tokenA), address(tokenB), AutoPoolYieldSource(payable(llSut)), mockProduct);
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.harvestRewards();
    }

    function testUpdateFarmInfoLLAP_OnlyGovernance() public {
        console.log("TJLLAP_YS_UFI_1: should be called only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        llSut.updateFarmInfo();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    ////////////////////////////////////////////////////////////////*/

    function _mockLatestRoundData() private {
        AggregatorV3Interface oracleX = AggregatorV3Interface(autoPoolVault.getOracleX());
        AggregatorV3Interface oracleY = AggregatorV3Interface(autoPoolVault.getOracleY());

        /// Mock the chainlink aggregator to return the updatedAt as latest timestamp for the data feeds
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleX.latestRoundData();

        vm.mockCall(
            address(oracleX),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
        );

        (roundId, answer, startedAt, updatedAt, answeredInRound) = oracleY.latestRoundData();
        vm.mockCall(
            address(oracleY),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
        );
    }
}
