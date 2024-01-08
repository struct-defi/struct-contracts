pragma solidity 0.8.11;

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import {WadMath} from "../../../../contracts/utils/WadMath.sol";

import "../../../common/fey-products/autopool/AutoPoolProductBaseTestSetupLive.sol";
import "../../../common/fey-products/autopool/AutoPoolProductHarness.sol";

contract FEYAutoPoolProductInvest_IntegrationTest is AutoPoolProductBaseTestSetupLive {
    using WadMath for uint256;

    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    uint256 private wavaxToBeInvested = 224847521055007055319;
    uint256 private usdcToBeInvested = 27021141;

    uint256 private leverageThresholdMin = 1250000;
    uint256 private leverageThresholdMax = 750000;

    AutoPoolProductHarness internal sutWAVAX;

    event Invested(
        uint256 _trancheTokensInvestedSenior,
        uint256 _trancheTokensInvestedJunior,
        uint256 _trancheTokensInvestableSenior,
        uint256 _trancheTokensInvestableJunior
    );

    event StatusUpdated(DataTypes.State currentStatus);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 33646790);

        super.setUp();
        makeInitialDeposits();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        uint256 _investmentTerm = 20 minutes;
        investTestsFixture(wavax, usdc, 1000e18, 20000e18, _investmentTerm);
    }

    function makeInitialDeposits() internal {
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, JUNIOR_TRANCHE, usdc);
    }

    function testForkInvestAP_RevertIfAlreadyInvested() public {
        console.log(
            "should revert with INVALID_STATE (code '22') when tried to call invest() when the product is already invested"
        );
        vm.warp(block.timestamp + 15 minutes);
        user1.invest();

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.invest();
    }

    function testForkInvestAP_ShouldUpdateProductStatus() public {
        console.log("should update the status of the product to `INVESTED`");
        vm.warp(block.timestamp + 15 minutes);
        user1.invest();
        assert(sut.getCurrentState() == DataTypes.State.INVESTED);
    }

    function testForkInvestAP_ShouldEmitInvestedEvent() public {
        console.log("should emit `Invested()` event");

        vm.warp(block.timestamp + 15 minutes);
        vm.expectEmit(true, true, true, false, address(sut));
        emit Invested(wavaxToBeInvested, usdcToBeInvested * 1e12, 0, 0);
        user1.invest();
    }

    function testForkInvestAP_ShouldEmitStatusUpdatedEvent() public {
        console.log("should emit `StatusUpdated()` event");

        vm.warp(block.timestamp + 15 minutes);
        vm.expectEmit(true, false, false, false, address(sut));
        emit StatusUpdated(DataTypes.State.INVESTED);

        user1.invest();
    }

    function testForkInvestAP_ShouldUpdateTokensInvestableAndExcess_Case1() public {
        /**
         * Case1 (no excess):
         *       juniorTokensInvestable (or) seniorTokensInvestable should be >= levMaxValue && <= levMinValue
         */

        console.log("should update `tokenInvested` and `tokensExcess` values when all the tokens are invested (case 1)");

        _deposit(user1, 100e18, SENIOR_TRANCHE, wavax);
        _deposit(user1, 2e6, JUNIOR_TRANCHE, usdc);

        vm.warp(block.timestamp + 15 minutes);

        DataTypes.TrancheInfo memory _trancheInfoSeniorBefore = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSeniorAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        /// Should invest all the senior tranche tokens
        assertEq(_trancheInfoSeniorBefore.tokensDeposited, _trancheInfoSeniorAfter.tokensInvestable);
        assertEq(_trancheInfoSeniorAfter.tokensExcess, 0);

        /// Should invest all the junior tranche tokens
        assertEq(_trancheInfoJuniorBefore.tokensDeposited, _trancheInfoJuniorAfter.tokensInvestable);
        assertEq(_trancheInfoJuniorAfter.tokensExcess, 0);
    }

    function testForkInvestAP_ShouldUpdateTokensInvestableAndExcess_Case2() public {
        /**
         * Case2:  seniorTrancheDeposits >> juniorTrancheDeposits
         *                Invest ALL Jr tranche tokens
         *                Investable senior tokens = jrDeposited * _srToJrRate *  10**6 / levThresholdMax
         *                Excess Senior = totalSeniorDeposits - investableSrTokens
         */

        console.log(
            "should update `tokenDeposited` and `tokensExcess` values when seniorTrancheDeposits is higher than juniorTrancheDeposits (case 2)"
        );

        _deposit(user1, 500e18, SENIOR_TRANCHE, wavax);
        _deposit(user1, 1e6, JUNIOR_TRANCHE, usdc);

        vm.warp(block.timestamp + 15 minutes);

        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 _trancheTokenRateSrToJr;

        (, _trancheTokenRateSrToJr,,) = sut.getTokenRate(JUNIOR_TRANCHE, 0);

        user1.invest();

        uint256 seniorTokensToBeInvested = (
            ((_trancheInfoJuniorBefore.tokensDeposited * _trancheTokenRateSrToJr) / 10 ** 18) * 10 ** 6
        ) / leverageThresholdMax;

        DataTypes.TrancheInfo memory _trancheInfoSeniorAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        /// Should invest all the junior tranche tokens
        assertEq(_trancheInfoJuniorBefore.tokensDeposited, _trancheInfoJuniorAfter.tokensInvestable);
        assertEq(_trancheInfoJuniorAfter.tokensExcess, 0);

        /// Should invest a part of the senior tranche tokens and set the remaining to junior tranche tokens as excess
        assertEq(_trancheInfoSeniorAfter.tokensInvestable, seniorTokensToBeInvested);
        assertEq(
            _trancheInfoSeniorAfter.tokensExcess, _trancheInfoSeniorAfter.tokensDeposited - seniorTokensToBeInvested
        );
    }

    function testForkInvestAP_ShouldUpdateTokensInvestableAndExcess_Case3() public {
        /**
         * Case3:  juniorTrancheDeposits > seniorTrancheDeposits
         *              Deposit all Sr tranche tokens
         *               Investable junior tokens = levMin * (srTokensDeposited * seniorTokenRate)
         *               Excess Junior = totalJuniorDeposits - investableJrTokens
         */

        console.log(
            "should update `tokensInvestable` and `tokensExcess` values when juniorTrancheDeposits is higher than seniorTrancheDeposits (case 3)"
        );
        vm.warp(block.timestamp + 15 minutes);
        DataTypes.TrancheInfo memory _trancheInfoSeniorBefore = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 _trancheTokenRateJrToSr;

        (, _trancheTokenRateJrToSr,,) = sut.getTokenRate(SENIOR_TRANCHE, 0);

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSeniorAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 juniorTokensToBeInvested =
            leverageThresholdMin * ((_trancheInfoSeniorBefore.tokensDeposited * _trancheTokenRateJrToSr) / 10 ** 18);
        juniorTokensToBeInvested /= 10 ** 6;

        /// Should invest all the senior tranche tokens
        assertEq(_trancheInfoSeniorBefore.tokensDeposited, _trancheInfoSeniorAfter.tokensInvestable);
        assertEq(_trancheInfoSeniorAfter.tokensExcess, 0);

        /// Should invest only a part of the junior tranche tokens since `jrTokensValue > srTokensValue`
        assertEq(_trancheInfoJuniorAfter.tokensInvestable, juniorTokensToBeInvested);
        assertEq(
            _trancheInfoJuniorAfter.tokensExcess, _trancheInfoJuniorBefore.tokensDeposited - juniorTokensToBeInvested
        );
    }

    function testForkInvestAP_UsdcAvaxProduct_ShouldEmitStatusUpdatedEvent() public {
        console.log("should emit `StatusUpdated()` event");

        sut = _createUsdcAvaxProduct(sut);
        user1 = new FEYProductUser(address(sut));

        _deposit(user1, 10e18, JUNIOR_TRANCHE, wavax);
        _deposit(user1, 100e6, SENIOR_TRANCHE, usdc);
        vm.warp(block.timestamp + 15 minutes);
        vm.expectEmit(true, false, false, false, address(sut));
        emit StatusUpdated(DataTypes.State.INVESTED);
        user1.invest();
    }

    /// Cases to make sure that the calculations are correct even if the order of tranche tokens are changed.

    function testForkInvestAP_UsdcAvaxProduct_ShouldUpdateTokensInvestableAndExcess_Case1() public {
        /**
         * Case1 (no excess):
         *       juniorTokensInvestable (or) seniorTokensInvestable should be >= levMaxValue && <= levMinValue
         */

        console.log("should update `tokenInvested` and `tokensExcess` values when all the tokens are invested (case 1)");
        sut = _createUsdcAvaxProduct(sut);
        user1 = new FEYProductUser(address(sut));
        _deposit(user1, 19e18, JUNIOR_TRANCHE, wavax);
        _deposit(user1, 200e6, SENIOR_TRANCHE, usdc);

        vm.warp(block.timestamp + 15 minutes);

        DataTypes.TrancheInfo memory _trancheInfoSeniorBefore = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSeniorAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        /// Should invest all the senior tranche tokens
        assertEq(
            _trancheInfoSeniorBefore.tokensDeposited,
            _trancheInfoSeniorAfter.tokensInvestable,
            "totalDeposited==totalInvestable - senior tranche"
        );
        assertEq(_trancheInfoSeniorAfter.tokensExcess, 0, "tokensExcess==0 - senior tranche");

        /// Should invest all the junior tranche tokens
        assertEq(
            _trancheInfoJuniorBefore.tokensDeposited,
            _trancheInfoJuniorAfter.tokensInvestable,
            "totalDeposited==totalInvestable - junior tranche"
        );
        assertEq(_trancheInfoJuniorAfter.tokensExcess, 0, "tokensExcess==0 - junior tranche");
    }

    function testForkInvestAP_UsdcAvaxProduct_ShouldUpdateTokensInvestableAndExcess_Case2() public {
        /**
         * Case2:  seniorTrancheDeposits >> juniorTrancheDeposits
         *                Invest ALL Jr tranche tokens
         *                Investable senior tokens = jrDeposited * _srToJrRate *  10**6 / levThresholdMax
         *                Excess Senior = totalSeniorDeposits - investableSrTokens
         */

        console.log(
            "should update `tokenDeposited` and `tokensExcess` values when seniorTrancheDeposits is higher than juniorTrancheDeposits (case 2)"
        );

        sut = _createUsdcAvaxProduct(sut);
        user1 = new FEYProductUser(address(sut));
        _deposit(user1, 10000e6, SENIOR_TRANCHE, usdc);
        _deposit(user1, 1e18, JUNIOR_TRANCHE, wavax);

        vm.warp(block.timestamp + 15 minutes);

        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 _trancheTokenRateSrToJr;

        (, _trancheTokenRateSrToJr,,) = sut.getTokenRate(JUNIOR_TRANCHE, 0);

        user1.invest();

        uint256 seniorTokensToBeInvested = (
            ((_trancheInfoJuniorBefore.tokensDeposited * _trancheTokenRateSrToJr) / 10 ** 18) * 10 ** 6
        ) / leverageThresholdMax;

        DataTypes.TrancheInfo memory _trancheInfoSeniorAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        /// Should invest all the junior tranche tokens
        assertEq(
            _trancheInfoJuniorBefore.tokensDeposited,
            _trancheInfoJuniorAfter.tokensInvestable,
            "deposited==invested ~ junior"
        );
        assertEq(_trancheInfoJuniorAfter.tokensExcess, 0, "excess==0 ~ junior");

        /// Should invest a part of the senior tranche tokens and set the remaining to junior tranche tokens as excess
        assertEq(_trancheInfoSeniorAfter.tokensInvestable, seniorTokensToBeInvested, "investable==invested ~ senior");
        assertEq(
            _trancheInfoSeniorAfter.tokensExcess,
            _trancheInfoSeniorAfter.tokensDeposited - seniorTokensToBeInvested,
            "excess==tokensDeposited-invested ~ senior"
        );
    }

    function testForkInvestAP_UsdcAvaxProduct_ShouldUpdateTokensInvestableAndExcess_Case3() public {
        /**
         * Case3:  juniorTrancheDeposits > seniorTrancheDeposits
         *              Deposit all Sr tranche tokens
         *               Investable junior tokens = levMin * (srTokensDeposited * seniorTokenRate)
         *               Excess Junior = totalJuniorDeposits - investableJrTokens
         */

        console.log(
            "should update `tokensInvestable` and `tokensExcess` values when juniorTrancheDeposits is higher than seniorTrancheDeposits (case 3)"
        );
        sut = _createUsdcAvaxProduct(sut);
        user1 = new FEYProductUser(address(sut));

        _deposit(user1, 1000e6, SENIOR_TRANCHE, usdc);
        _deposit(user1, 250e18, JUNIOR_TRANCHE, wavax);

        vm.warp(block.timestamp + 15 minutes);
        DataTypes.TrancheInfo memory _trancheInfoSeniorBefore = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 _trancheTokenRateJrToSr;

        (, _trancheTokenRateJrToSr,,) = sut.getTokenRate(SENIOR_TRANCHE, 0);

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSeniorAfter = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorAfter = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 juniorTokensToBeInvested =
            leverageThresholdMin * ((_trancheInfoSeniorBefore.tokensDeposited * _trancheTokenRateJrToSr) / 10 ** 18);
        juniorTokensToBeInvested /= 10 ** 6;

        /// Should invest all the senior tranche tokens
        assertEq(
            _trancheInfoSeniorBefore.tokensDeposited,
            _trancheInfoSeniorAfter.tokensInvestable,
            "deposited==investable ~ senior"
        );
        assertEq(_trancheInfoSeniorAfter.tokensExcess, 0, "excess==0 ~ senior");

        /// Should invest only a part of the junior tranche tokens since `jrTokensValue > srTokensValue`
        assertEq(_trancheInfoJuniorAfter.tokensInvestable, juniorTokensToBeInvested, "investable==invested ~ junior");
        assertEq(
            _trancheInfoJuniorAfter.tokensExcess,
            _trancheInfoJuniorBefore.tokensDeposited - juniorTokensToBeInvested,
            "excess==deposited-invested ~ junior"
        );
    }

    function _grantUserRoleOnNewProduct(address _user, address _product) internal {
        vm.startPrank(address(admin));
        gac.grantRole(WHITELISTED, _user);
        gac.grantRole(PRODUCT, _product);
        vm.stopPrank();
    }

    function _createUsdcAvaxProduct(AutoPoolProductHarness _product) internal returns (AutoPoolProductHarness) {
        uint256 _usdcTrancheCapacity = 100000e18; // 10k USDC
        uint256 _wavaxTrancheCapacity = 1000e18; // 100 AVAX

        /// Deploy FEYProduct
        DataTypes.TrancheConfig memory trancheConfigUSDC =
            DataTypes.TrancheConfig({tokenAddress: usdc, decimals: 6, spTokenId: 2, capacity: _usdcTrancheCapacity});

        DataTypes.TrancheConfig memory trancheConfigWAVAX =
            DataTypes.TrancheConfig({tokenAddress: wavax, decimals: 18, spTokenId: 3, capacity: _wavaxTrancheCapacity});

        DataTypes.ProductConfig memory productConfig = DataTypes.ProductConfig({
            poolId: 0,
            fixedRate: fixedRate,
            startTimeDeposit: block.timestamp,
            startTimeTranche: block.timestamp + 10 minutes,
            endTimeTranche: block.timestamp + 30 minutes,
            leverageThresholdMin: 1250000,
            leverageThresholdMax: 750000,
            managementFee: managementFee, // 1%
            performanceFee: performanceFee // 2%
        });

        DataTypes.InitConfigParam memory initConfigParams =
            DataTypes.InitConfigParam(trancheConfigUSDC, trancheConfigWAVAX, productConfig);
        _product = new AutoPoolProductHarness();
        vm.prank(address(admin));
        gac.grantRole(PRODUCT, address(_product));
        setupYieldSource(address(usdc), address(wavax));
        _product.initialize(
            initConfigParams,
            IStructPriceOracle(address(oracle)),
            ISPToken(address(spToken)),
            IGAC(address(gac)),
            IDistributionManager(distributionManager),
            address(yieldSource), // Yield Source
            payable(address(wavax))
        );
        return _product;
    }
}
