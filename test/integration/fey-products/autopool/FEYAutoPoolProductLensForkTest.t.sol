pragma solidity 0.8.11;

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Constants.sol";
import "@core/lens/FEYAutoPoolProductLens.sol";

import "@interfaces/IAutoPoolFEYProduct.sol";
import "@external/traderjoe/IAPTFarm.sol";

import {IAutoPoolYieldSource} from "@interfaces/IAutoPoolYieldSource.sol";

import {WadMath} from "../../../../contracts/utils/WadMath.sol";

import "../../../common/fey-products/autopool/AutoPoolProductBaseTestSetupLive.sol";

contract FEYAutoPoolProductLens_IntegrationTest is AutoPoolProductBaseTestSetupLive {
    using WadMath for uint256;

    IAPTFarm public constant APT_FARM = IAPTFarm(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C);

    FEYAutoPoolProductLens productLens;

    uint256 public wavaxToDeposit = 100e18;
    uint256 public usdcToDeposit = 2000e6;

    uint256 public wavaxCap = 1000e18;
    uint256 public usdcCap = 20000e18;

    // 1 year
    uint256 _investmentTerm = 8760 hours;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 31656449);

        super.setUp();
    }

    function onSetup() public virtual override {
        vm.clearMockedCalls();
        vm.mockCall(
            address(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C),
            abi.encodeWithSelector(IAPTFarm.vaultFarmId.selector),
            abi.encode(0)
        );

        IAPTFarm.FarmInfo memory _farmInfo = IAPTFarm.FarmInfo(
            IERC20(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d),
            13602996785183687529309514525636914715470,
            1691502560,
            12400793000000000,
            IRewarder(0x0000000000000000000000000000000000000000)
        );
        vm.mockCall(
            address(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C),
            abi.encodeWithSelector(IAPTFarm.farmInfo.selector),
            abi.encode(_farmInfo)
        );
        vm.mockCall(
            address(APT_FARM),
            abi.encodeWithSelector(IAPTFarm.hasFarm.selector, address(autoPoolVault)),
            abi.encode(true)
        );
        initOracle();
        investTestsFixture(usdc, wavax, usdcCap, wavaxCap, _investmentTerm);
        productLens = new FEYAutoPoolProductLens();
    }

    function testForkPreviewAllocateToTranchesAP_Success() public {
        console.log("should return the expected senior token allocation halfway through the product's term period");
        _deposit(user1, wavaxToDeposit, JUNIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, SENIOR_TRANCHE, usdc);
        vm.warp(block.timestamp + 10 minutes);
        user1.invest();
        /// 6 months == 0.5 years
        uint256 _investmentPeriodHalf = _investmentTerm / 2;
        vm.warp(block.timestamp + _investmentPeriodHalf);
        (uint256 _receivedSr,) = productLens.previewAllocateToTranches(IAutoPoolFEYProduct(address(sut)));

        DataTypes.TrancheInfo memory _trancheInfoSr = sut.getTrancheInfo(SENIOR_TRANCHE);
        /// expected tokens should be 102.5% of tokens investable because fixed rate is 5% APR and 6 months have passed
        uint256 _fixedRateAccumulated = fixedRate / 2;
        uint256 _srTokensExpected = _trancheInfoSr.tokensInvestable
            + ((_trancheInfoSr.tokensInvestable * _fixedRateAccumulated) / Constants.DECIMAL_FACTOR);
        assertEq(_receivedSr, _srTokensExpected, "tokens received sr");
    }

    function testFuzz_ForkPreviewAllocateToTranchesAP_Success(uint256 _wavaxToDeposit, uint256 _usdcToDeposit) public {
        console.log("should return the expected senior token allocation halfway through the product's term period");
        _wavaxToDeposit = bound(_wavaxToDeposit, 1e18, wavaxCap);
        _usdcToDeposit = bound(_usdcToDeposit, 1e6, usdcCap / 10 ** 12);
        _deposit(user1, _wavaxToDeposit, JUNIOR_TRANCHE, wavax);
        _deposit(user2, _usdcToDeposit, SENIOR_TRANCHE, usdc);
        vm.warp(block.timestamp + 10 minutes);
        user1.invest();
        /// 6 months == 0.5 years
        uint256 _investmentPeriodHalf = _investmentTerm / 2;
        vm.warp(block.timestamp + _investmentPeriodHalf);
        (uint256 _receivedSr,) = productLens.previewAllocateToTranches(IAutoPoolFEYProduct(address(sut)));

        DataTypes.TrancheInfo memory _trancheInfoSr = sut.getTrancheInfo(SENIOR_TRANCHE);
        /// expected tokens should be 102.5% of tokens investable because fixed rate is 5% APR and 6 months have passed
        uint256 _fixedRateAccumulated = fixedRate / 2;
        uint256 _srTokensExpected = _trancheInfoSr.tokensInvestable
            + (_trancheInfoSr.tokensInvestable * _fixedRateAccumulated / Constants.DECIMAL_FACTOR);
        assertEq(_receivedSr, _srTokensExpected, "tokens received sr");
    }
    /// forge-config: default.fuzz.runs = 512

    function testForkPreviewAllocateToTranchesAP_InvalidState() public {
        console.log("should return 0 for both tranches if product state is not invested");
        (uint256 _receivedSr, uint256 _receivedJr) =
            productLens.previewAllocateToTranches(IAutoPoolFEYProduct(address(sut)));
        assertEq(_receivedSr, 0, "tokens received sr");
        assertEq(_receivedJr, 0, "tokens received jr");
    }

    function testForkGetMarketTokensReceived_NonZero() public {
        console.log("should return a non-zero amount for both tranche tokens");
        _deposit(user1, wavaxToDeposit, JUNIOR_TRANCHE, wavax);
        _deposit(user2, usdcToDeposit, SENIOR_TRANCHE, usdc);
        vm.warp(block.timestamp + 10 minutes);
        user1.invest();

        IAutoPoolYieldSource _usdcWavaxYieldSource = IAutoPoolYieldSource(address(yieldSource));
        (uint256 _amountA, uint256 _amountB,,) = productLens.getMarketTokensReceived(_usdcWavaxYieldSource);

        assertGt(_amountA, 0, "_amountA > 0");
        assertGt(_amountB, 0, "_amountB > 0");
    }
}
