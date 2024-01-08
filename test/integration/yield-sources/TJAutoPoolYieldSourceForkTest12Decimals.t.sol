pragma solidity 0.8.11;

import "../../common/yield-sources/YieldSourceBaseTestSetup.sol";

contract AutoPoolYieldSource_IntegrationTest is YieldSourceBaseTestSetup {
    IERC20Metadata tokenA;
    IERC20Metadata tokenB;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 33646790);
        autoPoolVault = autoPoolVault_AVAX_USDC;

        super.setUp();
        tokenA = sut.tokenA();
        tokenB = sut.tokenB();
    }

    function testConstructorAP_ShouldInitializeWithCorrectTokens() public {
        assertEq(address(sut.tokenA()), address(autoPoolVault.getTokenX()));
        assertEq(address(sut.tokenB()), address(autoPoolVault.getTokenY()));
    }

    function testSupplyTokensAP_ShouldUpdateTotalShares() public {
        console.log("should update the total shares and it should be equal to sum of product shares");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);

        assertEq(
            sut.totalShares(),
            sut.productAPTShare(mockProduct) + sut.productAPTShare(mockProduct2) + sut.productAPTShare(mockProduct3)
        );
    }

    function testSupplyTokensAP_ShouldUpdateTotalAutoPoolShareTokens() public {
        uint256 atpShareTokens = sut.totalAutoPoolShareTokens();
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        assertGt(sut.totalAutoPoolShareTokens(), atpShareTokens);

        atpShareTokens = sut.totalAutoPoolShareTokens();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);
        assertGt(sut.totalAutoPoolShareTokens(), atpShareTokens);
        atpShareTokens = sut.totalAutoPoolShareTokens();
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);
        assertGt(sut.totalAutoPoolShareTokens(), atpShareTokens);
    }

    function testSupplyTokensAP_ShouldEmitTokensSuppliedEvent() public {
        address tokenA = address(tokenA);
        address tokenB = address(tokenB);
        address caller = address(mockProduct);

        uint256 tokenAToSupply = 10e18;
        uint256 tokenAPrice = _getPrice(tokenA);
        uint256 tokenBRatePerTokenA = ((tokenAPrice * 1e18) / _getPrice(tokenB));
        uint256 tokenBToSupply = (tokenAToSupply * tokenBRatePerTokenA) / 1e18;
        uint256 tokenADecimals = IERC20Metadata(tokenA).decimals();
        uint256 tokenBDecimals = IERC20Metadata(tokenB).decimals();
        /// This is required as YieldSource contract uses `transferFrom()` for `supplyTokens()`
        deal(tokenA, address(caller), 100e18);
        deal(tokenB, address(caller), 100e18);
        vm.startPrank(caller);
        IERC20(tokenA).approve(address(sut), 100e18);
        IERC20(tokenB).approve(address(sut), 100e18);
        vm.expectEmit(true, true, true, true, address(sut));
        emit TokensSupplied(10e18, 140280435000000000000, 352404893238202);
        sut.supplyTokens(10e18, 140280435);
        vm.stopPrank();
    }

    function testQueueForRedemptionAP_ShouldUpdateTotalShares() public {
        console.log("should subtract the totalShares with the product shares");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        uint256 product1Shares = sut.productAPTShare(mockProduct);
        uint256 totalSharesBefore = sut.totalShares();

        vm.prank(mockProduct);
        sut.queueForRedemption();
        uint256 totalSharesAfter = sut.totalShares();

        assertEq(totalSharesAfter, totalSharesBefore - product1Shares);

        vm.prank(mockProduct2);
        sut.queueForRedemption();
        assertEq(sut.totalShares(), 0);
    }

    function testQueueForRedemptionAP_ShouldUpdateProductShares() public {
        console.log("should set the productShares to 0 after redemption");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        uint256 product1Shares = sut.productAPTShare(mockProduct);
        uint256 product2Shares = sut.productAPTShare(mockProduct);

        // Make sure that the product shares are non-zero before redemption
        assertGt(product1Shares, 0);
        assertGt(product2Shares, 0);

        vm.prank(mockProduct);
        sut.queueForRedemption();
        product1Shares = sut.productAPTShare(mockProduct);
        assertEq(product1Shares, 0);

        vm.prank(mockProduct2);
        sut.queueForRedemption();

        product2Shares = sut.productAPTShare(mockProduct);
        assertEq(product2Shares, 0);
    }

    function testQueueForRedemptionAP_ShouldUpdateTotalAPTokenShares() public {
        console.log("should update the atpShareTokensTotal value");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        vm.prank(mockProduct);
        sut.queueForRedemption();
        uint256 _apShareTokenTotal = sut.totalAutoPoolShareTokens();
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalance = _userInfo.amount;
        assertGt(_apShareTokenTotal, 0, "1: _apShareTokenTotal==0");
        assertEq(_apShareTokenTotal, _apShareTokenBalance, "_apShareTokenTotal==_apShareTokenBalance");

        vm.prank(mockProduct2);
        sut.queueForRedemption();
        _apShareTokenTotal = sut.totalAutoPoolShareTokens();

        assertEq(_apShareTokenTotal, 0, "2: _apShareTokenTotal==0");
    }

    function testQueueForRedemptionAP_ShouldEmitRedemptionQueuedEvent() public {
        console.log("should emit `RedemptionQueued` Event with correct product address and roundId");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        vm.startPrank(mockProduct);
        vm.expectEmit(true, true, true, true);
        emit RedemptionQueued(mockProduct, autoPoolVault.getCurrentRound());
        sut.queueForRedemption();
        vm.stopPrank();

        vm.startPrank(mockProduct2);
        vm.expectEmit(true, true, true, true);
        emit RedemptionQueued(mockProduct2, autoPoolVault.getCurrentRound());
        sut.queueForRedemption();
        vm.stopPrank();
    }

    function testQueueForRedemptionAP_ShouldRevertWhenNoShares() public {
        console.log("should revert when tried to redeem when there are no shares");

        // Redeeming without supplying should revert
        vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.NoShares.selector));
        vm.prank(mockProduct);
        sut.queueForRedemption();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.prank(mockProduct);
        sut.queueForRedemption();

        // Should be able to redeem only once
        vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.NoShares.selector));
        vm.prank(mockProduct);
        sut.queueForRedemption();
    }

    function testRedeemTokensAP_ShouldUpdateLastProcessedRound() public {
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

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.prank(mockProduct);
        sut.queueForRedemption();
        assertEq(sut.nextRoundIndexToBeProcessed(), 0);
        _simulateExecuteQueuedWithdrawls();

        sut.redeemTokens();
        assertEq(sut.nextRoundIndexToBeProcessed(), 1);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);
        vm.prank(mockProduct2);
        sut.queueForRedemption();

        vm.prank(mockProduct3);
        sut.queueForRedemption();

        _simulateExecuteQueuedWithdrawls();

        sut.redeemTokens();
        assertEq(sut.nextRoundIndexToBeProcessed(), 2);
    }

    function testQueueRedemptionAP_ShouldUpdateRoundInfo_totalShares() public {
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

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);

        uint256 _productShares = sut.productAPTShare(address(mockProduct));
        vm.prank(mockProduct);
        sut.queueForRedemption();
        DataTypes.Round memory _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalShares, 0);
        assertEq(_roundInfo.totalShares, _productShares);

        _simulateExecuteQueuedWithdrawls();

        sut.redeemTokens();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);

        uint256 _product2Shares = sut.productAPTShare(address(mockProduct2));
        uint256 _product3Shares = sut.productAPTShare(address(mockProduct3));

        vm.prank(mockProduct2);
        sut.queueForRedemption();

        vm.prank(mockProduct3);
        sut.queueForRedemption();

        _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalShares, 0);
        assertEq(_roundInfo.totalShares, _product2Shares + _product3Shares);
    }

    function testQueueRedemptionAP_ShouldUpdateRoundInfo_totalAutoPoolTokens() public {
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

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);

        uint256 _autoPoolShareTokensBalanceBefore = sut.totalAutoPoolShareTokens();
        vm.prank(mockProduct);
        sut.queueForRedemption();
        uint256 _autoPoolShareTokensBalanceAfter = sut.totalAutoPoolShareTokens();

        DataTypes.Round memory _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalAutoPoolTokens, 0);
        assertEq(_roundInfo.totalAutoPoolTokens, _autoPoolShareTokensBalanceBefore - _autoPoolShareTokensBalanceAfter);

        _simulateExecuteQueuedWithdrawls();

        sut.redeemTokens();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);

        _autoPoolShareTokensBalanceBefore = sut.totalAutoPoolShareTokens();

        vm.prank(mockProduct2);
        sut.queueForRedemption();

        vm.prank(mockProduct3);
        sut.queueForRedemption();
        _autoPoolShareTokensBalanceAfter = sut.totalAutoPoolShareTokens();
        _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertGt(_roundInfo.totalAutoPoolTokens, 0);
        assertEq(_roundInfo.totalAutoPoolTokens, _autoPoolShareTokensBalanceBefore - _autoPoolShareTokensBalanceAfter);
    }

    function testQueueRedemptionAP_ShouldUpdateRoundInfo_ProductsAndShares() public {
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

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        uint256 _productShares = sut.productAPTShare(address(mockProduct));

        vm.prank(mockProduct);
        sut.queueForRedemption();

        uint256 _currentRound = autoPoolVault.getCurrentRound();
        DataTypes.Round memory _roundInfo = sut.getRoundInfo(_currentRound);

        assertEq(_roundInfo.products.length, 1);
        assertEq(_roundInfo.shares.length, 1);

        assertEq(_roundInfo.products[0], mockProduct);
        assertEq(_roundInfo.shares[0], _productShares);

        _simulateExecuteQueuedWithdrawls();

        sut.redeemTokens();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);

        uint256 _product2Shares = sut.productAPTShare(address(mockProduct2));
        uint256 _product3Shares = sut.productAPTShare(address(mockProduct3));

        vm.prank(mockProduct2);
        sut.queueForRedemption();

        vm.prank(mockProduct3);
        sut.queueForRedemption();

        _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound());

        assertEq(_roundInfo.products.length, 2);
        assertEq(_roundInfo.shares.length, 2);

        assertEq(_roundInfo.products[0], mockProduct2);
        assertEq(_roundInfo.shares[0], _product2Shares);

        assertEq(_roundInfo.products[1], mockProduct3);
        assertEq(_roundInfo.shares[1], _product3Shares);
    }

    function testRedeemTokensAP_ShouldUpdateRoundInfo_redeemed() public {
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

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.prank(mockProduct);
        sut.queueForRedemption();
        _simulateExecuteQueuedWithdrawls();
        DataTypes.Round memory _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound() - 1);
        assertEq(_roundInfo.redeemed, false);

        sut.redeemTokens();
        _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound() - 1);

        assertEq(_roundInfo.redeemed, true);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct2);

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct3);
        vm.prank(mockProduct2);
        sut.queueForRedemption();

        vm.prank(mockProduct3);
        sut.queueForRedemption();

        _simulateExecuteQueuedWithdrawls();

        sut.redeemTokens();
        _roundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound() - 1);

        assertEq(_roundInfo.redeemed, true);
    }

    function testQueueForRedemptionAP_ShouldRevertIfRoundOccupied() public {
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
            _simulateSupply(address(tokenA), address(tokenB), sut, products[i]);
            vm.prank(products[i]);
            sut.queueForRedemption();
        }

        DataTypes.Round memory _currentRoundInfo = sut.getRoundInfo(autoPoolVault.getCurrentRound());

        assert(
            _currentRoundInfo.products.length == _currentRoundInfo.shares.length
                && _currentRoundInfo.products.length == 5 // since max iteration = 5
        );

        /// Assert that first 5 products are in current round and the remaining 5 products are queues for the next round
        for (uint256 i; i < 5; i++) {
            assertEq(_currentRoundInfo.products[i], products[i]);
        }
        uint256 tokenABalanceBefore = tokenA.balanceOf(address(sut));
        uint256 tokenBBalanceBefore = tokenB.balanceOf(address(sut));
        for (uint256 i = 5; i < 10; i++) {
            _simulateSupply(address(tokenA), address(tokenB), sut, products[i]);
            vm.startPrank(products[i]);

            vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.RoundOccupied.selector));
            sut.queueForRedemption();

            vm.stopPrank();
        }
        uint256 tokenABalanceAfter = tokenA.balanceOf(address(sut));
        uint256 tokenBBalanceAfter = tokenB.balanceOf(address(sut));

        assertEq(tokenABalanceBefore, tokenABalanceAfter);
        assertEq(tokenBBalanceBefore, tokenBBalanceAfter);
    }

    function testRedeemTokensAP_ShouldReturnIfMaxIterationsHit() public {
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

            _simulateSupply(address(tokenA), address(tokenB), sut, products[i]);
            vm.prank(products[i]);
            sut.queueForRedemption();
        }
        // Round Id 74
        _simulateExecuteQueuedWithdrawls();
        /// Now the current round Id is 75, the rounds 73 and 74 should be processed on this call.
        sut.redeemTokens();

        DataTypes.Round memory _currentRoundInfo = sut.getRoundInfo(currentRound);
        DataTypes.Round memory _nextRoundInfo = sut.getRoundInfo(currentRound + 1);

        /// Since the round 73 has 10 products already, only those products will be processed and the next round 74 will be skipped since the max iterations=10
        assertEq(_currentRoundInfo.redeemed, true, "only current round is executed");
        assertEq(_nextRoundInfo.redeemed, false, "next round is skipped");

        /// Still, the latest roundId is 75, but last processed roundId is 73. So this time round 74 should be processed.
        sut.redeemTokens();
        _nextRoundInfo = sut.getRoundInfo(currentRound + 1);
        assertEq(_nextRoundInfo.redeemed, true, "next round is processed");
    }

    function testRedeemTokensAP_ShouldRevertIfInvalidCaller() public {
        console.log("should revert with error code `29` if caller is not KEEPER");

        vm.startPrank(mockProduct);
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.redeemTokens();
    }
    /// GAC ////

    function testSupplyTokensAP_RevertWhenLocalPaused() public {
        console.log("should revert when the contract is paused locally");

        vm.prank(pauser);
        sut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        sut.supplyTokens(120, 120);
    }

    function testSupplyTokensAP_RevertWhenGlobalPaused() public {
        console.log("should revert when the contract is paused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        sut.supplyTokens(120, 120);
    }

    function testSupplyTokensAP_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused locally");

        vm.prank(pauser);
        sut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        sut.supplyTokens(120, 120);

        vm.prank(pauser);
        sut.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.supplyTokens(120, 120);
    }

    function testSupplyTokensAP_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        sut.supplyTokens(120, 120);

        vm.prank(pauser);
        gac.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.supplyTokens(120, 120);
    }

    function testQueueForRedemptionAP_RevertWhenLocalPaused() public {
        console.log("should revert when the contract is paused locally");

        vm.prank(pauser);
        sut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        sut.queueForRedemption();
    }

    function testQueueForRedemptionAP_RevertWhenGlobalPaused() public {
        console.log("should revert when the contract is paused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        sut.queueForRedemption();
    }

    function testQueueForRedemptionAP_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused locally");

        vm.prank(pauser);
        sut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        sut.queueForRedemption();

        vm.prank(pauser);
        sut.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.queueForRedemption();
    }

    function testQueueForRedemptionAP_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
        console.log("should revert with a different error message when the contract is unpaused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        sut.queueForRedemption();

        vm.prank(pauser);
        gac.unpause();

        // Should revert with a different error, implies that `gacPausable` check has been passed.
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.queueForRedemption();
    }

    function testSetMaxIterations_ShouldUpdateMaxIterations() public {
        console.log("should update the maxIterations value");

        assertEq(sut.maxIterations(), 5);

        vm.prank(admin);
        sut.setMaxIterations(15);

        assertEq(sut.maxIterations(), 15);
    }

    function testSetMaxIterations_ShouldEmitMaxIterationsUpdatedEvent() public {
        console.log("should emit `MaxIterationsUpdated` event");

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(sut));
        emit MaxIterationsUpdated(15);
        sut.setMaxIterations(15);
    }

    function testSetMaxIterations_ShouldRevert_IfInputZero() public {
        console.log("should revert if 0 is passed as input");

        vm.prank(admin);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ZERO_VALUE));
        sut.setMaxIterations(0);
    }

    function testSetMaxIterations_ShouldRevert_IfCalledFromNonGovernanceAccount() public {
        console.log("should revert the caller doesn't have `GOVERNANCE` role");

        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.setMaxIterations(10);
    }

    function testRecompoundRewardsAP_WithSingleReward() public {
        console.log("should harvest, swap and redeposit funds to the pool and restake atp vault share tokens");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceBefore = _userInfo.amount;
        sut.recompoundRewards();
        _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceAfter = _userInfo.amount;
        assertGt(_apShareTokenBalanceAfter, _apShareTokenBalanceBefore);
    }

    function testRecompoundRewardsAP_TotalSharesNoUpdate_SingleReward() public {
        console.log("should NOT update total shares value on recompound");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceBefore = _userInfo.amount;
        uint256 _totalSharesBefore = sut.totalShares();

        sut.recompoundRewards();
        _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceAfter = _userInfo.amount;
        uint256 _totalSharesAfter = sut.totalShares();

        uint256 _tokensStaked = _apShareTokenBalanceAfter - _apShareTokenBalanceBefore;
        uint256 _shares = sut.sharesToTokens(_tokensStaked, _totalSharesAfter, sut.totalAutoPoolShareTokens());

        assertEq(_totalSharesAfter, _totalSharesBefore, "_totalSharesAfter == _totalSharesBefore");
    }

    function testRecompoundRewardsAP_UpdateTotalAPTShareTokens_SingleReward() public {
        console.log("should update totalAutoPoolShareTokens value everytime");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceBefore = _userInfo.amount;
        uint256 _totalShareTokensBefore = sut.totalAutoPoolShareTokens();

        sut.recompoundRewards();
        _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceAfter = _userInfo.amount;
        uint256 _totalShareTokensAfter = sut.totalAutoPoolShareTokens();

        uint256 _tokensStaked = _apShareTokenBalanceAfter - _apShareTokenBalanceBefore;

        assertGt(_totalShareTokensAfter, _totalShareTokensBefore, "_totalShareTokensAfter > _totalShareTokensBefore");
        assertEq((_totalShareTokensAfter - _totalShareTokensBefore), _tokensStaked);
    }

    function testRecompoundRewardsAP_ShouldEmitTokensFarmedEvent() public {
        console.log("should emit `TokensFarmed` event");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceBefore = _userInfo.amount;

        vm.recordLogs();
        sut.recompoundRewards();

        _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _apShareTokenBalanceAfter = _userInfo.amount;

        uint256 _tokensStaked = _apShareTokenBalanceAfter - _apShareTokenBalanceBefore;

        Vm.Log[] memory entries = vm.getRecordedLogs();

        /// Subtract 2, since the last event is RecompoundRewards() and last before event is TokensFarmed()
        assertEq(entries[entries.length - 2].topics[0], keccak256("TokensFarmed(uint256)"));
        assertEq(abi.decode(entries[entries.length - 2].data, (uint256)), _tokensStaked);
    }

    function testRecompoundRewardsAP_ShouldEmitRewardsRecompoundedEvent() public {
        console.log("should emit `RewardsRecompounded` event");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.recordLogs();
        sut.recompoundRewards();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(
            entries[entries.length - 1].topics[0], keccak256("RewardsRecompounded(uint256,uint256,uint256,uint256)")
        );
    }

    function testRecompoundRewardsAP_ShouldSwapRewards1_WithSingleReward() public {
        console.log("should swap reward1 if the reward token is neither tokenA nor tokenB");

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);

        vm.recordLogs();
        sut.recompoundRewards();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(
            entries[entries.length - 1].topics[0], keccak256("RewardsRecompounded(uint256,uint256,uint256,uint256)")
        );

        (uint256 _rewards1, uint256 _rewards2, uint256 _harvestedTokenA, uint256 _harvestedTokenB) =
            abi.decode(entries[entries.length - 1].data, (uint256, uint256, uint256, uint256));
        assertGt(_rewards1, 0, "_rewards1 > 0");
        assertEq(_rewards2, 0, "_rewards2 == 0");

        uint256 _harvestedTokenAValue = _getPrice(address(tokenA)) * _harvestedTokenA / 1e18;
        uint256 _harvestedTokenBValue = _getPrice(address(tokenB)) * (_harvestedTokenB * 1e12) / 1e18;
        uint256 _rewards1Value = _getPrice(address(joe)) * _rewards1 / 1e18;
        /// Reward1 value should be (almost) equal to harvestedTokenValues A and B combined.
        assertApproxEqRel(_harvestedTokenAValue + _harvestedTokenBValue, _rewards1Value, 0.05e18); // approx equal 5%
    }

    function testRecompoundRewardsAP_ShouldNotSwapRewards_WithDualReward_NonNative() public {
        console.log("should not swap if reward2 is tokenA: WAVAX");

        MockRewarder _mockRewarder = new MockRewarder(address(tokenA),false);
        deal(address(tokenA), address(_mockRewarder), 100e20);
        console.log("file: TJAutoPoolYieldSourceForkTest.t.sol:872", tokenA.balanceOf(address(_mockRewarder)));

        vm.prank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2); // APTFarm Owner
        aptFarm.set(0, 12400793000000000, IRewarder(address(_mockRewarder)), true);

        AutoPoolYieldSource sut2 =
            new AutoPoolYieldSource(autoPoolVault,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(tokenA), address(tokenB), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        vm.recordLogs();
        sut2.recompoundRewards();

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
        uint256 _rewards2Value = _getPrice(address(tokenA)) * _rewards2 / 1e18;

        /// Reward1 + Reward2 value should be (almost) equal to harvestedTokenValues A and B combined.
        assertApproxEqRel(_harvestedTokenAValue + _harvestedTokenBValue, _rewards1Value + _rewards2Value, 0.05e18); // approx equal 5%
    }

    function testRecompoundRewardsAP_ShouldNotSwapRewards_WithDualReward_Native() public {
        console.log("should not swap if reward2 is tokenA: AVAX");

        MockRewarder _mockRewarder = new MockRewarder(address(0),true);
        deal(address(_mockRewarder), 100e20);

        vm.prank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2); // APTFarm Owner
        aptFarm.set(0, 12400793000000000, IRewarder(address(_mockRewarder)), true);

        AutoPoolYieldSource sut2 =
            new AutoPoolYieldSource(autoPoolVault,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(tokenA), address(tokenB), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        vm.recordLogs();
        sut2.recompoundRewards();

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
        uint256 _rewards2Value = _getPrice(address(tokenA)) * _rewards2 / 1e18;

        /// Reward1 + Reward2 value should be (almost) equal to harvestedTokenValues A and B combined.
        assertApproxEqRel(_harvestedTokenAValue + _harvestedTokenBValue, _rewards1Value + _rewards2Value, 0.05e18); // approx equal 5%
    }

    function testRecompoundRewardsAP_ShouldSwapRewards_WithDualReward() public {
        console.log("should not swap if reward2 is neither tokenA nor tokenB");

        MockRewarder _mockRewarder = new MockRewarder(address(dai),false);
        deal(address(dai), address(_mockRewarder), 100e20);

        vm.prank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2); // APTFarm Owner
        aptFarm.set(0, 12400793000000000, IRewarder(address(_mockRewarder)), true);

        AutoPoolYieldSource sut2 =
            new AutoPoolYieldSource(autoPoolVault,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(tokenA), address(tokenB), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        vm.recordLogs();
        sut2.recompoundRewards();

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
        uint256 _rewards2Value = _getPrice(address(dai)) * _rewards2 / 1e18;

        /// Reward1 + Reward2 value should be (almost) equal to harvestedTokenValues A and B combined.
        assertApproxEqRel(_harvestedTokenAValue + _harvestedTokenBValue, _rewards1Value + _rewards2Value, 0.05e18); // approx equal 5%
    }

    function testRecompoundRewardsAP_ShouldRevert_IfInvalidRate() public {
        console.log("should revert if the rate difference exceeds Max deviation");

        vm.mockCall(
            address(structOracle),
            abi.encodeWithSelector(IStructPriceOracle.getAssetPrice.selector, address(tokenA)),
            abi.encode(5e18)
        );
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        vm.expectRevert(abi.encodePacked(Errors.PFE_RATEDIFF_EXCEEDS_DEVIATION));
        sut.recompoundRewards();
        vm.clearMockedCalls();
    }

    function testRecompoundRewardsAP_WithoutFarm() public {
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

    function testQueueForRedemptionAP_WithoutFarm() public {
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

    function testHarvestRewardsAP_WithSingleReward() public {
        console.log("should harvest reward1 from the APTFarm");
        console.log(sut.numRewards(), sut.aptFarmId());
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        uint256 _reward1BalanceBefore = joe.balanceOf(address(sut));
        vm.prank(admin);
        sut.harvestRewards();
        uint256 _reward1BalanceAfter = joe.balanceOf(address(sut));

        assertGt(_reward1BalanceAfter, _reward1BalanceBefore);
    }

    function testHarvestRewardsAP_WithDualReward() public {
        console.log("should harvest reward1 and reward2 from APTFarm");

        MockRewarder _mockRewarder = new MockRewarder(address(dai),false);
        deal(address(dai), address(_mockRewarder), 100e20);

        vm.prank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2); // APTFarm Owner
        aptFarm.set(0, 12400793000000000, IRewarder(address(_mockRewarder)), true);

        AutoPoolYieldSource sut2 =
            new AutoPoolYieldSource(autoPoolVault,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        _simulateSupply(address(tokenA), address(tokenB), sut2, mockProduct);
        vm.warp(block.timestamp + 0.5 days);
        uint256 _reward1BalanceBefore = joe.balanceOf(address(sut2));
        uint256 _reward2BalanceBefore = dai.balanceOf(address(sut2));
        vm.prank(admin);
        sut2.harvestRewards();
        uint256 _reward1BalanceAfter = joe.balanceOf(address(sut2));
        uint256 _reward2BalanceAfter = dai.balanceOf(address(sut2));

        assertGt(_reward1BalanceAfter, _reward1BalanceBefore, "_reward1BalanceAfter > _reward1BalanceBefore");
        assertGt(_reward2BalanceAfter, _reward2BalanceBefore, "_reward2BalanceAfter, _reward2BalanceBefore");
    }

    function testHarvestRewardsAP_OnlyGovernance() public {
        console.log("harvest rewards should be called only by GOVERNANCE");
        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.harvestRewards();
    }

    function testUpdateFarmInfoAP_OnlyGovernance() public {
        console.log("TJAP_YS_UFI_1: should be called only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.updateFarmInfo();
    }

    function testUpdateFarmInfoAP_ShouldUpdateFarmInfo_SingleReward() public {
        console.log("TJAP_YS_UFI_2: should update farm info: single reward");

        assertEq(sut.numRewards(), 1);
        assertEq(address(sut.rewardToken2()), address(0));
        assertEq(sut.aptFarmId(), 0);

        vm.mockCall(address(aptFarm), abi.encodeWithSelector(IAPTFarm.hasFarm.selector), abi.encode(false));

        vm.prank(admin);
        sut.updateFarmInfo();

        assertEq(sut.numRewards(), 0);
        assertEq(sut.aptFarmId(), type(uint256).max);
    }

    function testUpdateFarmInfoAP_ShouldUpdateFarmInfo_DualReward_NonNative() public {
        console.log("TJAP_YS_UFI_3: should update farm info: dual reward - non native");

        assertEq(sut.numRewards(), 1);
        assertEq(address(sut.rewardToken2()), address(0));

        MockRewarder _mockRewarder = new MockRewarder(address(tokenA),false);
        deal(address(tokenA), address(_mockRewarder), 100e20);

        vm.prank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2); // APTFarm Owner
        aptFarm.set(0, 12400793000000000, IRewarder(address(_mockRewarder)), true);

        vm.prank(admin);
        sut.updateFarmInfo();

        assertEq(sut.numRewards(), 2);
        assertEq(address(sut.rewardToken2()), address(tokenA));
        assertEq(sut.isReward2Native(), false);
    }

    function testUpdateFarmInfoAP_ShouldUpdateFarmInfo_DualReward_Native() public {
        console.log("TJAP_YS_UFI_4: should update farm info: dual reward - native");

        assertEq(sut.numRewards(), 1);
        assertEq(address(sut.rewardToken2()), address(0));

        MockRewarder _mockRewarder = new MockRewarder(address(0),true);
        deal(address(_mockRewarder), 100e20);

        vm.prank(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2); // APTFarm Owner
        aptFarm.set(0, 12400793000000000, IRewarder(address(_mockRewarder)), true);

        vm.prank(admin);
        sut.updateFarmInfo();

        assertEq(sut.numRewards(), 2);
        assertEq(address(sut.rewardToken2()), address(0));
        assertEq(sut.isReward2Native(), true);
    }

    function testUpdateFarmInfoAP_ShouldDepositToFarm() public {
        console.log("TJAP_YS_UFI_6: should deposit aptTokens to farm");

        /// Simulate no farm state in yield source to accumulate aptTokens in the yieldsource contract.
        vm.mockCall(address(aptFarm), abi.encodeWithSelector(IAPTFarm.hasFarm.selector), abi.encode(false));
        vm.prank(admin);
        sut.updateFarmInfo();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);

        IAPTFarm.UserInfo memory _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _aptTokensInFarmBefore = _userInfo.amount;
        uint256 _aptTokensInSutBefore = autoPoolVault.balanceOf(address(sut));
        vm.clearMockedCalls();

        vm.prank(admin);
        sut.updateFarmInfo();

        _userInfo = aptFarm.userInfo(0, address(sut));
        uint256 _aptTokensInFarmAfter = _userInfo.amount;
        uint256 _aptTokensInSutAfter = autoPoolVault.balanceOf(address(sut));

        assertEq(_aptTokensInFarmBefore, 0, "_aptTokensInFarmBefore == 0");
        assertEq(_aptTokensInSutAfter, 0, "_aptTokensInSutAfter == 0");

        assertGt(_aptTokensInSutBefore, 0, "_aptTokensInSutBefore > 0");

        /// Should deposit all the aptTokens to farm
        assertEq(_aptTokensInFarmAfter, _aptTokensInSutBefore, "_aptTokensInSutBefore == _aptTokensInFarmAfter");
    }

    function testUpdateFarmInfoAP_ShouldEmitTokensFarmed() public {
        console.log("TJAP_YS_UFI_5: should emit tokensFarmed event");

        /// Simulate no farm state in yield source to accumulate aptTokens in the yieldsource contract.
        vm.mockCall(address(aptFarm), abi.encodeWithSelector(IAPTFarm.hasFarm.selector), abi.encode(false));
        vm.prank(admin);
        sut.updateFarmInfo();

        _simulateSupply(address(tokenA), address(tokenB), sut, mockProduct);

        vm.clearMockedCalls();

        uint256 _apShareTokenBalance = autoPoolVault.balanceOf(address(sut));

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(sut));
        emit TokensFarmed(_apShareTokenBalance);
        sut.updateFarmInfo();
        vm.stopPrank();
    }
}
