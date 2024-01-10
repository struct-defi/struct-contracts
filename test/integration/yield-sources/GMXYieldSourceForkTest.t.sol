pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@mocks/MockERC20.sol";
import "@interfaces/IGAC.sol";
import "@core/common/StructPriceOracle.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Helpers.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../../common/yield-sources/GMXYieldSourceHarness.sol";

import "../../common/BaseTestSetup.sol";

contract GMXYieldSource_IntegrationTest is BaseTestSetup {
    /// System under test
    GMXYieldSourceHarness internal sut;

    uint256 seniorTrancheTokensExpectedAtMaturity = 100e18;

    IERC20Metadata internal constant wavax = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20Metadata internal constant usdc = IERC20Metadata(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);

    AggregatorV3Interface internal constant avax_usdc_feed =
        AggregatorV3Interface(0x0A77230d17318075983913bC2145DB16C7366156);

    AggregatorV3Interface internal constant usdc_usd_feed =
        AggregatorV3Interface(0xF096872672F44d6EBA71458D74fe67F9a77a23B9);

    StructPriceOracle internal structOracle;

    event TokensSupplied(uint256 amountAIn, uint256 amountBIn, uint256 fsGMXReceived);
    event TokensRedeemed(uint256 amountARedeemed, uint256 amountBRedeemed);
    event RewardsAdded(address indexed productAddress);

    event RewardsRecompounded();

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 27503190);
        super.setUp();
    }

    function onSetup() public virtual override {
        AggregatorV3Interface[] memory sources = new AggregatorV3Interface[](2);
        sources[0] = avax_usdc_feed;
        sources[1] = usdc_usd_feed;

        address[] memory assets = new address[](2);
        assets[0] = address(wavax);
        assets[1] = address(usdc);

        structOracle = new StructPriceOracle(assets, sources);

        setLabels();

        vm.prank(mockFactory);

        sut = new GMXYieldSourceHarness(mockFactory, address(gac));
        sut.populateProductInfo(address(mockProduct), address(wavax), address(usdc), 18, 6);
        sut.populateProductInfo(address(mockProduct2), address(usdc), address(usdc), 6, 6);
        sut.populateProductInfo(address(mockProduct3), address(wavax), address(wavax), 18, 18);
    }

    function setLabels() internal {
        vm.label(mockFactory, "MockFactory");
        vm.label(address(wavax), "wAVAX");
        vm.label(address(usdc), "USDC");
        vm.label(address(sut), "GMXYieldSource");
        vm.label(address(structOracle), "StructPriceOracle");
    }

    function testSupplyTokensGMX_ShouldUpdateTotalShares() public {
        console.log("should update the total shares and it should be equal to sum of product shares");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);
        _simulateSupply(address(wavax), address(wavax), sut, mockProduct3);
        DataTypes.FEYGMXProductInfo memory productInfo1 = sut.getFEYGMXProductInfo(address(mockProduct));
        DataTypes.FEYGMXProductInfo memory productInfo2 = sut.getFEYGMXProductInfo(address(mockProduct2));
        DataTypes.FEYGMXProductInfo memory productInfo3 = sut.getFEYGMXProductInfo(address(mockProduct3));
        assertEq(sut.getTotalShares(), productInfo1.shares + productInfo2.shares + productInfo3.shares);
    }

    function testSupplyTokensGMX_ShouldUpdatefsGLPReceived() public {
        console.log("should update the product info struct with the fsGMXReceived amount");
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        DataTypes.FEYGMXProductInfo memory productInfo = sut.getFEYGMXProductInfo(address(mockProduct));

        assertEq(sut.getTotalShares(), productInfo.shares);
    }

    function testSupplyTokensGMX_ShouldUpdatefsGLPTokensTotal() public {
        console.log("should update the fsGLPTokensTotal value whenever tokens are supplied to the pool");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        assertEq(sut.getfsGlpTokensTotal(), 4196633397279529767306);
    }

    function testSupplyTokensGMX_ShouldEmitTokensSuppliedEvent() public {
        console.log("should emit TokensSupplied event with the correct params");
        address tokenA = address(wavax);
        address tokenB = address(usdc);
        address caller = address(mockProduct);

        uint256 tokenAToSupply = 10e18;
        uint256 tokenAPrice = getPrice(tokenA);
        uint256 tokenBRatePerTokenA = ((tokenAPrice * 1e18) / getPrice(tokenB));
        uint256 tokenBToSupply = (tokenAToSupply * tokenBRatePerTokenA) / 1e18;
        uint256 tokenADecimals = IERC20Metadata(tokenA).decimals();
        uint256 tokenBDecimals = IERC20Metadata(tokenB).decimals();
        uint256 tokenAToSupplyInTokenDecimals = Helpers.weiToTokenDecimals(tokenADecimals, tokenAToSupply);
        uint256 tokenBToSupplyInTokenDecimals = Helpers.weiToTokenDecimals(tokenBDecimals, tokenBToSupply);
        /// This is required as YieldSource contract uses `transferFrom()` for `supplyTokens()`
        deal(tokenA, address(caller), 100e18);
        deal(tokenB, address(caller), 100e18);
        vm.startPrank(caller);
        IERC20(tokenA).approve(address(sut), 100e18);
        IERC20(tokenB).approve(address(sut), 100e18);

        vm.expectEmit(true, true, true, true, address(sut));
        emit TokensSupplied(10000000000000000000, 157813133000000000000, 419663338395605123850);
        sut.supplyTokens(tokenAToSupplyInTokenDecimals, tokenBToSupplyInTokenDecimals);
        vm.stopPrank();
    }

    function testSupplyTokensGMX_RevertWhenLocalPaused() public {
        console.log("should revert when the contract is paused locally");

        vm.prank(pauser);
        sut.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_LOCAL_PAUSED));
        sut.supplyTokens(120, 120);
    }

    function testSupplyTokensGMX_RevertWhenGlobalPaused() public {
        console.log("should revert when the contract is paused globally");

        vm.prank(pauser);
        gac.pause();

        vm.expectRevert(abi.encodePacked(Errors.ACE_GLOBAL_PAUSED));
        sut.supplyTokens(120, 120);
    }

    function testSupplyTokensGMX_ShouldThrowDifferentRevertMessageLocalUnpaused() public {
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

    function testSupplyTokensGMX_ShouldThrowDifferentRevertMessageGlobalUnpaused() public {
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

    function testSupplyTokensGMX_ShouldRevert_WhenSuppliedTwice() public {
        console.log("should revert if a product tries to supply tokens more than once");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);

        vm.startPrank(mockProduct);
        vm.expectRevert(abi.encodeWithSelector(IGMXYieldSource.AlreadySupplied.selector));
        sut.supplyTokens(120, 120);
        vm.stopPrank();
    }

    function testRecompoundRewardsGMX_Revert_InvalidAccess() public {
        console.log("should revert if the caller does not have KEEPER role");

        vm.prank(mockProduct);
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.recompoundRewards();
    }

    function testRecompoundRewardsGMX_ShouldEmitRewardsRecompoundedEvent() public {
        console.log("should emit RewardsRecompounded event");
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 2 weeks);

        vm.expectEmit(true, true, true, true, address(sut));
        emit RewardsRecompounded();
        sut.recompoundRewards();
    }

    function testRecompoundRewardsGMX_ShouldReInvestRewards_SingleProduct() public {
        console.log("should harvest rewards and re-invest the rewards when there's only one product");
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);

        vm.warp(block.timestamp + 2 days);

        uint256 _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();

        sut.recompoundRewards();

        uint256 _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();

        assertGt(_fsGLPBalanceAfter, _fsGLPBalanceBefore);
    }

    function testRecompoundRewardsGMX_ShouldReInvestRewards_MultipleProducts() public {
        console.log("should harvest rewards and re-invest the rewards when there are multiple products");

        /// First product supplies liquidity (WAVAX / USDC)
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 2 days);

        uint256 _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();

        sut.recompoundRewards();

        uint256 _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();

        assertGe(_fsGLPBalanceAfter, _fsGLPBalanceBefore);

        /// Second product supplies liquidity (USDC / USDC)
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        vm.warp(block.timestamp + 4 days);

        _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();

        sut.recompoundRewards();

        _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();

        assertGe(_fsGLPBalanceAfter, _fsGLPBalanceBefore);

        /// The next product supplies liquidity (WAVAX/WAVAX)
        _simulateSupply(address(wavax), address(wavax), sut, mockProduct3);

        vm.warp(block.timestamp + 6 days);

        _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();

        sut.recompoundRewards();

        _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();

        assertGe(_fsGLPBalanceAfter, _fsGLPBalanceBefore);
    }

    function testRedeemTokensGMX_ShouldRedeemTokens() public {
        console.log("tokenA redeemed should be approximately greater or equal to the expected senior tranche tokens");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);

        uint256 delta = 0.005e18; //0.5%
        vm.prank(mockProduct);
        (uint256 _tokenARedeemed, uint256 _tokenBRedeeemed) = sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);
        /// Use assertApproxEqRel as both the tranche tokens are different
        assertApproxEqRel(_tokenARedeemed, seniorTrancheTokensExpectedAtMaturity, delta);

        /// Product2
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        vm.prank(mockProduct2);
        (_tokenARedeemed, _tokenBRedeeemed) = sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);
        console.log("_tokenARedeemed", _tokenARedeemed);
        /// Use assertGe as both the tranche tokens are same
        assertGe(_tokenARedeemed * 10 ** 12, seniorTrancheTokensExpectedAtMaturity);
    }

    function testRedeemTokensGMX_ShouldUpdatefsGlpTotal() public {
        console.log("should subtract the fsGlpTokensTotal");
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        uint256 fsGlpTokensTotalBefore = sut.getfsGlpTokensTotal();
        DataTypes.FEYGMXProductInfo memory productInfo = sut.getFEYGMXProductInfo(address(mockProduct));
        uint256 _tokens = sut.sharesToTokens(productInfo.shares, fsGlpTokensTotalBefore);

        vm.prank(mockProduct);
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);
        uint256 fsGlpTokensTotalAfter = sut.getfsGlpTokensTotal();

        assertEq(fsGlpTokensTotalBefore - _tokens, fsGlpTokensTotalAfter);

        /// Redeem from Product2
        fsGlpTokensTotalBefore = sut.getfsGlpTokensTotal();
        productInfo = sut.getFEYGMXProductInfo(address(mockProduct2));
        _tokens = sut.sharesToTokens(productInfo.shares, fsGlpTokensTotalBefore);

        vm.prank(mockProduct2);
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);
        fsGlpTokensTotalAfter = sut.getfsGlpTokensTotal();

        assertEq(fsGlpTokensTotalAfter, 0);

        assertEq(fsGlpTokensTotalBefore - _tokens, fsGlpTokensTotalAfter);
    }

    function testRedeemTokensGMX_ShouldUpdateTotalShares() public {
        console.log("should update the total shares");
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        DataTypes.FEYGMXProductInfo memory product2Info = sut.getFEYGMXProductInfo(address(mockProduct2));

        vm.prank(mockProduct);
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);

        /// Product1 shares should be deducted
        assertEq(product2Info.shares, sut.getTotalShares());

        /// Redeem from Product2

        vm.prank(mockProduct2);

        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);

        /// Should be zero since all the products withdrew
        assertEq(sut.getTotalShares(), 0);
    }

    function testRedeemTokensGMX_ShouldEmitTokensRedeemedEvent() public {
        console.log("should emit TokensRedeemed event with the correct params");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);

        vm.startPrank(mockProduct);
        vm.expectEmit(true, true, true, true, address(sut));
        emit TokensRedeemed(100000000000000000131, 1562334964);

        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);
        vm.stopPrank();
    }

    function testRedeemTokensGMX_ShouldSetProductSharesToZero() public {
        console.log("should set the shares of the product to Zero after redemption");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        DataTypes.FEYGMXProductInfo memory productInfoBefore = sut.getFEYGMXProductInfo(address(mockProduct));

        vm.prank(mockProduct);
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);

        DataTypes.FEYGMXProductInfo memory productInfoAfter = sut.getFEYGMXProductInfo(address(mockProduct));

        assertGt(productInfoBefore.shares, 0);
        assertEq(productInfoAfter.shares, 0);
    }

    function testRedeemTokensGMX_ShouldSendRedeemedTokensToProducts() public {
        console.log("should send the redeemed tokens to the product contracts");

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(wavax), address(wavax), sut, mockProduct3);

        uint256 tokenABalanceBefore = wavax.balanceOf(address(mockProduct));
        uint256 tokenBBalanceBefore = usdc.balanceOf(address(mockProduct));

        vm.prank(mockProduct);
        (uint256 tokenARedeemed, uint256 tokenBRedeemed) = sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);

        uint256 tokenABalanceAfter = wavax.balanceOf(address(mockProduct));
        uint256 tokenBBalanceAfter = usdc.balanceOf(address(mockProduct));

        assertEq(tokenABalanceAfter, tokenARedeemed + tokenABalanceBefore, "wavax redeemed");
        assertEq(tokenBBalanceAfter, tokenBRedeemed + tokenBBalanceBefore, "usdc redeemed");

        /// redeem from product3
        tokenABalanceBefore = wavax.balanceOf(address(mockProduct3));

        vm.prank(mockProduct3);
        (tokenARedeemed, tokenBRedeemed) = sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);

        tokenABalanceAfter = wavax.balanceOf(address(mockProduct3));
        // both tranche tokens are wAVAX, so tokenABalanceAfter should be equal
        // to tokenARedeemed + tokenBRedeemed + tokenABalanceBefore
        assertEq(tokenABalanceAfter, tokenARedeemed + tokenBRedeemed + tokenABalanceBefore, "product3 tokens redeemed");
    }

    function testRedeemTokensGMX_ShouldRevert_WhenThereAreNoShares() public {
        console.log("should revert with `NoShares()` if a product tries to redeemTokens when there are no shares");

        vm.startPrank(mockProduct);
        vm.expectRevert(abi.encodeWithSelector(IGMXYieldSource.NoShares.selector, address(mockProduct)));
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity); // Redemption before supplying should revert
        vm.stopPrank();

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.startPrank(mockProduct);

        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity); // Redeem once

        vm.expectRevert(abi.encodeWithSelector(IGMXYieldSource.NoShares.selector, address(mockProduct)));
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity); // Redeem twice (should revert)
        vm.stopPrank();
    }

    function testRedeemTokensGMX_ShouldRedeemAllAsTokenA() public {
        console.log(
            "should redeem all the fsGlp tokens allocated to the product as tokenA if the expectedTokenAAmount is more than the fsGlp tokens allocated"
        );

        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        vm.startPrank(mockProduct);

        uint256 _delta = 0.0075e18; //0.75%
        seniorTrancheTokensExpectedAtMaturity = 200e18;
        (uint256 _tokenARedeemed, uint256 _tokenBRedeemed) = sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity); // Redemption before supplying should revert
        assertEq(_tokenBRedeemed, 0); // all the allocated fsGlp tokens should be redeemed for tokenA
        assertApproxEqRel(_tokenARedeemed, seniorTrancheTokensExpectedAtMaturity, _delta);
        vm.stopPrank();
    }

    function testAddRewardsGMX_ShouldAddRewards_OneProduct() public {
        console.log("should update shares, totalShares and fsGlpTokensTotal when there's one product");

        /// First product supplies liquidity (WAVAX / USDC)
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 2 days);

        uint256 _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();
        DataTypes.FEYGMXProductInfo memory _productInfoBefore = sut.getFEYGMXProductInfo(address(mockProduct));
        uint256 _totalSharesBefore = sut.getTotalShares();

        uint256 _rewardAmount = 100e18;
        deal(address(wavax), address(sut), _rewardAmount);
        address[] memory _products = new address[](1);
        _products[0] = address(mockProduct);
        vm.prank(admin);
        sut.addRewards(_products, _rewardAmount);

        uint256 _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();
        DataTypes.FEYGMXProductInfo memory _productInfoAfter = sut.getFEYGMXProductInfo(address(mockProduct));
        uint256 _totalSharesAfter = sut.getTotalShares();

        /// Make sure that the fsGLPToken balance is updated
        assertGt(_fsGLPBalanceAfter, _fsGLPBalanceBefore);

        /// Make sure that the shares are added
        assertGt(_totalSharesAfter - _totalSharesBefore, 0);

        /// All the added shares should be allocated to the product
        assertEq(_totalSharesAfter - _totalSharesBefore, _productInfoAfter.shares - _productInfoBefore.shares);
    }

    function testAddRewardsGMX_ShouldEmitEvent() public {
        console.log("should emit RewardsAdded event");

        /// First product supplies liquidity (WAVAX / USDC)
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 2 days);

        uint256 _rewardAmount = 100e18;
        deal(address(wavax), address(sut), _rewardAmount);
        address[] memory _products = new address[](1);
        _products[0] = address(mockProduct);
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit RewardsAdded(address(mockProduct));
        sut.addRewards(_products, _rewardAmount);
    }

    function testAddRewardsGMX_ShouldRevert_InsuffcientRewards() public {
        console.log("should revert if the expected rewards in more than the actual value");

        /// First product supplies liquidity (WAVAX / USDC)
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        vm.warp(block.timestamp + 2 days);

        uint256 _actualReward = 100e18;
        uint256 _expectedReward = _actualReward + 1;

        deal(address(wavax), address(sut), _actualReward);
        address[] memory _products = new address[](1);
        _products[0] = address(mockProduct);

        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IGMXYieldSource.InsufficientRewards.selector, _actualReward, _expectedReward)
        );
        sut.addRewards(_products, _expectedReward);
    }

    function testAddRewardsGMX_ShouldRevert_IfNoShares() public {
        console.log("should revert if the product has no deposits yet");

        uint256 _rewards = 100e18;
        deal(address(wavax), address(sut), _rewards);
        address[] memory _products = new address[](1);
        _products[0] = address(mockProduct);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGMXYieldSource.NoShares.selector, address(mockProduct)));
        sut.addRewards(_products, _rewards);
    }

    function testAddRewardsGMX_ShouldAddRewards_MultipleProducts() public {
        console.log("should update shares, totalShares and fsGlpTokensTotal when there are multiple products");

        /// 2 product supplies liquidity
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        vm.warp(block.timestamp + 2 days);

        uint256 _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();
        DataTypes.FEYGMXProductInfo memory _product1InfoBefore = sut.getFEYGMXProductInfo(address(mockProduct));
        DataTypes.FEYGMXProductInfo memory _product2InfoBefore = sut.getFEYGMXProductInfo(address(mockProduct2));
        uint256 _totalSharesBefore = sut.getTotalShares();

        uint256 _rewardAmount = 100e18;
        deal(address(wavax), address(sut), _rewardAmount);
        address[] memory _products = new address[](2);
        _products[0] = address(mockProduct);
        _products[1] = address(mockProduct2);
        vm.prank(admin);
        sut.addRewards(_products, _rewardAmount);

        uint256 _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();
        DataTypes.FEYGMXProductInfo memory _product1InfoAfter = sut.getFEYGMXProductInfo(address(mockProduct));
        DataTypes.FEYGMXProductInfo memory _product2InfoAfter = sut.getFEYGMXProductInfo(address(mockProduct2));

        uint256 _totalSharesAfter = sut.getTotalShares();

        uint256 _sharesPerProduct = (_totalSharesAfter - _totalSharesBefore) / 2;

        /// Make sure that the fsGLPToken balance is updated
        assertGt(_fsGLPBalanceAfter, _fsGLPBalanceBefore, "_fsGLPBalanceAfter > _fsGLPBalanceBefore");

        /// Make sure that the shares per product are > 0
        assertGt(_sharesPerProduct, 0, "_sharesPerProduct > 0");

        /// Make sure that the shares are equally distributed b/w the products
        assertEq(_sharesPerProduct, _product1InfoAfter.shares - _product1InfoBefore.shares, "Product1 Shares");
        assertEq(_sharesPerProduct, _product2InfoAfter.shares - _product2InfoBefore.shares, "Product2 Shares");
    }

    function testAddRewardsGMX_ShouldRevert_MultipleProducts() public {
        console.log("should revert if one of the products has no shares");

        ///  Product 1 supplies liquidity
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);

        vm.warp(block.timestamp + 2 days);

        uint256 _fsGLPBalanceBefore = sut.getfsGlpTokensTotal();
        uint256 _totalSharesBefore = sut.getTotalShares();

        uint256 _rewardAmount = 100e18;
        deal(address(wavax), address(sut), _rewardAmount);
        address[] memory _products = new address[](2);
        _products[0] = address(mockProduct);
        _products[1] = address(mockProduct2);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGMXYieldSource.NoShares.selector, address(mockProduct2)));
        sut.addRewards(_products, _rewardAmount);

        uint256 _fsGLPBalanceAfter = sut.getfsGlpTokensTotal();

        uint256 _totalSharesAfter = sut.getTotalShares();
        /// Make sure that the fsGLPToken balance remains the same
        assertEq(_fsGLPBalanceAfter, _fsGLPBalanceBefore, "_fsGLPBalanceAfter == _fsGLPBalanceBefore");

        /// Make sure that the totalShares remains the same
        assertEq(_totalSharesAfter, _totalSharesBefore, "__totalSharesAfter == __totalSharesBefore");
    }

    function testFsGlpTokensTotal_EqualsBalance() public {
        console.log("fsGlpTokensTotal should return the same value as fsGLP.balanceOf(yieldSource)");
        /// 2 product supplies liquidity
        _simulateSupply(address(wavax), address(usdc), sut, mockProduct);
        _simulateSupply(address(usdc), address(usdc), sut, mockProduct2);

        vm.warp(block.timestamp + 2 days);

        /// add rewards
        uint256 _rewardAmount = 100e18;
        deal(address(wavax), address(sut), _rewardAmount);
        address[] memory _products = new address[](2);
        _products[0] = address(mockProduct);
        _products[1] = address(mockProduct2);
        vm.prank(admin);
        sut.addRewards(_products, _rewardAmount);

        /// redeem second product
        vm.prank(mockProduct2);
        sut.redeemTokens(seniorTrancheTokensExpectedAtMaturity);

        /// recompound rewards
        vm.warp(block.timestamp + 6 days);
        sut.recompoundRewards();

        IERC20Metadata fsGLP = sut.FSGLP();
        uint256 _balanceTotalFsGlp = fsGLP.balanceOf(address(sut));
        uint256 _fsGlpTokensTotal = sut.getfsGlpTokensTotal();

        assertGt(_balanceTotalFsGlp, 0, "_balanceTotalFsGlp > 0");
        assertEq(_balanceTotalFsGlp, _fsGlpTokensTotal, "fsGLP balance == _fsGlpTokensTotal");
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    //////////////////////////////////////////////////////////////*/
    function _simulateSupply(address tokenA, address tokenB, GMXYieldSourceHarness _sut, address caller) internal {
        uint256 tokenADecimals = IERC20Metadata(tokenA).decimals();
        uint256 tokenBDecimals = IERC20Metadata(tokenB).decimals();
        uint256 tokenAToSupply = 100e18;
        uint256 tokenAPrice = getPrice(tokenA);
        uint256 tokenBRatePerTokenA = ((tokenAPrice * 1e18) / getPrice(tokenB));
        uint256 tokenBToSupply = (tokenAToSupply * tokenBRatePerTokenA) / 1e18;
        uint256 tokenAToSupplyInTokenDecimals = Helpers.weiToTokenDecimals(tokenADecimals, tokenAToSupply);
        uint256 tokenBToSupplyInTokenDecimals = Helpers.weiToTokenDecimals(tokenBDecimals, tokenBToSupply);
        vm.startPrank(caller);
        /// This is required as YieldSource contract uses `transferFrom()` for `supplyTokens()`
        if (tokenA == tokenB) {
            deal(tokenA, address(caller), tokenAToSupplyInTokenDecimals + tokenBToSupplyInTokenDecimals);
            IERC20(tokenA).approve(address(_sut), tokenAToSupplyInTokenDecimals + tokenBToSupplyInTokenDecimals);
        } else {
            deal(tokenA, address(caller), tokenAToSupplyInTokenDecimals);
            deal(tokenB, address(caller), tokenBToSupplyInTokenDecimals);
            IERC20(tokenA).approve(address(_sut), tokenAToSupplyInTokenDecimals);
            IERC20(tokenB).approve(address(_sut), tokenBToSupplyInTokenDecimals);
        }

        _sut.supplyTokens(tokenAToSupplyInTokenDecimals, tokenBToSupplyInTokenDecimals);

        vm.stopPrank();
    }

    function getPrice(address _asset) internal view returns (uint256) {
        return structOracle.getAssetPrice(_asset);
    }
}
