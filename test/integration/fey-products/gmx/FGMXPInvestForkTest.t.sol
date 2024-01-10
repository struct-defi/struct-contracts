pragma solidity 0.8.11;

import "@interfaces/IGMXYieldSource.sol";

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Constants.sol";
import "@core/libraries/helpers/Errors.sol";
import {WadMath} from "../../../../contracts/utils/WadMath.sol";

import "../../../common/fey-products/gmx/GMXProductBaseTestSetupLive.sol";

contract FGMXPInvest_IntegrationTest is GMXProductBaseTestSetupLive {
    using WadMath for uint256;

    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    uint256 private wavaxToBeInvested = 224847521055007055319;
    uint256 private usdcToBeInvested = 27021141;

    uint256 private leverageThresholdMin = 1250000;
    uint256 private leverageThresholdMax = 750000;

    GMXProductHarness internal sutWAVAX;

    event Invested(
        uint256 _trancheTokensInvestedSenior,
        uint256 _trancheTokensInvestedJunior,
        uint256 _trancheTokensInvestableSenior,
        uint256 _trancheTokensInvestableJunior
    );

    event StatusUpdated(DataTypes.State currentStatus);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 24540193);

        super.setUp();
        makeInitialDeposits();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();

        initOracle();
        investTestsFixture(wavax, usdc, 1000e18, 20000e18);
    }

    function makeInitialDeposits() internal {
        _deposit(user1, wavaxToDeposit, SENIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, JUNIOR_TRANCHE, usdc);
    }

    function testForkInvest_RevertIfAlreadyInvested() public {
        console.log(
            "should revert with INVALID_STATE (code '22') when tried to call invest() when the product is already invested"
        );
        _warpAndMockYieldSourceCalls();
        user1.invest();

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_STATE));
        user1.invest();
    }

    function testForkInvest_ShouldUpdateProductStatus() public {
        console.log("should update the status of the product to `INVESTED`");
        _warpAndMockYieldSourceCalls();
        user1.invest();
        assert(sut.getCurrentState() == DataTypes.State.INVESTED);
    }

    function testForkInvest_ShouldEmitInvestedEvent() public {
        console.log("should emit `Invested()` event");

        _warpAndMockYieldSourceCalls();
        vm.expectEmit(true, true, true, false, address(sut));
        emit Invested(wavaxToBeInvested, usdcToBeInvested * 1e12, 0, 0);
        user1.invest();
    }

    function testForkInvest_ShouldEmitStatusUpdatedEvent() public {
        console.log("should emit `StatusUpdated()` event");

        _warpAndMockYieldSourceCalls();
        vm.expectEmit(true, false, false, false, address(sut));
        emit StatusUpdated(DataTypes.State.INVESTED);

        user1.invest();
    }

    function testForkInvest_ShouldUpdateTokensInvestableAndExcess_Case1() public {
        /**
         * Case1 (no excess):
         *       juniorTokensInvestable (or) seniorTokensInvestable should be >= levMaxValue && <= levMinValue
         */

        console.log("should update `tokenInvested` and `tokensExcess` values when all the tokens are invested (case 1)");

        _deposit(user1, 100e18, SENIOR_TRANCHE, wavax);
        _deposit(user1, 2e6, JUNIOR_TRANCHE, usdc);

        _warpAndMockYieldSourceCalls();

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

    function testForkInvest_ShouldUpdateTokensInvestableAndExcess_Case2() public {
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

        _warpAndMockYieldSourceCalls();

        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);

        uint256 _trancheTokenRateSrToJr = sut.getTokenRate(JUNIOR_TRANCHE);

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

    function testForkInvest_ShouldUpdateTokensInvestableAndExcess_Case3() public {
        /**
         * Case3:  juniorTrancheDeposits > seniorTrancheDeposits
         *              Deposit all Sr tranche tokens
         *               Investable junior tokens = levMin * (srTokensDeposited * seniorTokenRate)
         *               Excess Junior = totalJuniorDeposits - investableJrTokens
         */

        console.log(
            "should update `tokensInvestable` and `tokensExcess` values when juniorTrancheDeposits is higher than seniorTrancheDeposits (case 3)"
        );
        _warpAndMockYieldSourceCalls();
        DataTypes.TrancheInfo memory _trancheInfoSeniorBefore = sut.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJuniorBefore = sut.getTrancheInfo(JUNIOR_TRANCHE);
        uint256 _trancheTokenRateJrToSr = sut.getTokenRate(SENIOR_TRANCHE);
        console.log(
            "testForkInvest_ShouldUpdateTokensInvestableAndExcess_Case3 ~ _trancheTokenRateJrToSr:",
            _trancheTokenRateJrToSr
        );

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

    function testForkInvest_SuccessBothTrancheTokenswAVAX_EqualTranches() public {
        console.log("Test ID: GMX_Pr_Inv_2");
        console.log("should invest product when both tranches have wAVAX tokens and are equal in value");
        sutWAVAX = _createNewProductSameToken(address(wavax), sutWAVAX);
        user1 = new FEYProductUser(address(sutWAVAX));

        _grantUserRoleOnNewProduct(address(user1), address(sutWAVAX));

        uint256 _amountToDeposit = 1e18;
        deal(address(wavax), address(user1), _amountToDeposit * 2);
        user1.increaseAllowance(address(wavax), _amountToDeposit * 2);
        user1.depositToJunior(_amountToDeposit);
        user1.depositToSenior(_amountToDeposit);

        _warpAndMockYieldSourceCalls();

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSenior = sutWAVAX.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJunior = sutWAVAX.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(_trancheInfoSenior.tokensInvestable, _amountToDeposit);
        assertEq(_trancheInfoSenior.tokensExcess, 0);
        assertEq(_trancheInfoJunior.tokensInvestable, _amountToDeposit);
        assertEq(_trancheInfoJunior.tokensExcess, 0);
    }

    function testForkInvest_SuccessBothTrancheTokenswAVAX_SeniorTrancheExcess() public {
        console.log("Test ID: GMX_Pr_Inv_3");
        console.log("should invest product when both tranches have wAVAX tokens and senior tranche is larger");
        sutWAVAX = _createNewProductSameToken(address(wavax), sutWAVAX);
        user1 = new FEYProductUser(address(sutWAVAX));

        _grantUserRoleOnNewProduct(address(user1), address(sutWAVAX));

        uint256 _amountToDeposit = 1e18;
        deal(address(wavax), address(user1), _amountToDeposit * 3);
        user1.increaseAllowance(address(wavax), _amountToDeposit * 3);
        user1.depositToJunior(_amountToDeposit);
        user1.depositToSenior(_amountToDeposit * 2);

        // 1 to 1 rate
        uint256 _srToJrRate = 10 ** 18;

        uint256 _leverageThresholdMax = 750_000;
        uint256 _investableSrTokens =
            (_amountToDeposit.wadMul(_srToJrRate) * Constants.DECIMAL_FACTOR) / _leverageThresholdMax;
        uint256 _amountExcessSr = _amountToDeposit * 2 - _investableSrTokens;

        vm.warp(block.timestamp + 15 minutes);
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.supplyTokens.selector),
            abi.encode(_investableSrTokens, _amountToDeposit)
        );

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSenior = sutWAVAX.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJunior = sutWAVAX.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(_trancheInfoSenior.tokensInvestable, _investableSrTokens, "Senior tokens investable");
        assertEq(_trancheInfoSenior.tokensExcess, _amountExcessSr, "Senior tokens excess");
        assertEq(_trancheInfoJunior.tokensInvestable, _amountToDeposit, "Junior tokens investable");
        assertEq(_trancheInfoJunior.tokensExcess, 0, "Junior tokens excess");
    }

    function testForkInvest_SuccessBothTrancheTokenswAVAX_JuniorTrancheExcess() public {
        console.log("Test ID: GMX_Pr_Inv_4");
        console.log("should invest product when both tranches have wAVAX tokens and junior tranche is larger");
        sutWAVAX = _createNewProductSameToken(address(wavax), sutWAVAX);
        user1 = new FEYProductUser(address(sutWAVAX));

        _grantUserRoleOnNewProduct(address(user1), address(sutWAVAX));

        uint256 _amountToDeposit = 1e18;
        deal(address(wavax), address(user1), _amountToDeposit * 3);
        user1.increaseAllowance(address(wavax), _amountToDeposit * 3);
        user1.depositToJunior(_amountToDeposit * 2);
        user1.depositToSenior(_amountToDeposit);

        // 1 to 1 rate
        uint256 _jrToSrRate = 10 ** 18;

        uint256 _leverageThresholdMin = 1_250_000;
        uint256 _investableJrTokens =
            (_leverageThresholdMin * _amountToDeposit.wadMul(_jrToSrRate)) / Constants.DECIMAL_FACTOR;
        uint256 _amountExcessJr = _amountToDeposit * 2 - _investableJrTokens;

        vm.warp(block.timestamp + 15 minutes);
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.supplyTokens.selector),
            abi.encode(_amountToDeposit, _investableJrTokens)
        );

        user1.invest();

        DataTypes.TrancheInfo memory _trancheInfoSenior = sutWAVAX.getTrancheInfo(SENIOR_TRANCHE);
        DataTypes.TrancheInfo memory _trancheInfoJunior = sutWAVAX.getTrancheInfo(JUNIOR_TRANCHE);

        assertEq(_trancheInfoSenior.tokensInvestable, _amountToDeposit, "Senior tokens investable");
        assertEq(_trancheInfoSenior.tokensExcess, 0, "Senior tokens excess");
        assertEq(_trancheInfoJunior.tokensInvestable, _investableJrTokens, "Junior tokens investable");
        assertEq(_trancheInfoJunior.tokensExcess, _amountExcessJr, "Junior tokens excess");
    }

    function _createNewProductSameToken(address _trancheToken, GMXProductHarness _product)
        internal
        returns (GMXProductHarness)
    {
        uint256 _trancheCapacity = 1000 * 10 ** IERC20Metadata(_trancheToken).decimals();
        /// Deploy FEYProduct
        DataTypes.TrancheConfig memory trancheConfigSr = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(_trancheToken),
            decimals: IERC20Metadata(_trancheToken).decimals(),
            spTokenId: 2,
            capacity: _trancheCapacity
        });

        DataTypes.TrancheConfig memory trancheConfigJr = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(_trancheToken),
            decimals: IERC20Metadata(_trancheToken).decimals(),
            spTokenId: 3,
            capacity: _trancheCapacity
        });

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
            DataTypes.InitConfigParam(trancheConfigSr, trancheConfigJr, productConfig);
        _product = new GMXProductHarness();
        setupYieldSource();
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

    function _grantUserRoleOnNewProduct(address _user, address _product) internal {
        vm.startPrank(address(admin));
        gac.grantRole(WHITELISTED, _user);
        gac.grantRole(PRODUCT, _product);
        vm.stopPrank();
    }

    function _warpAndMockYieldSourceCalls() internal {
        vm.warp(block.timestamp + 15 minutes);
        vm.mockCall(
            address(yieldSource),
            abi.encodeWithSelector(IGMXYieldSource.supplyTokens.selector),
            abi.encode(wavaxToBeInvested, usdcToBeInvested)
        );
    }
}
