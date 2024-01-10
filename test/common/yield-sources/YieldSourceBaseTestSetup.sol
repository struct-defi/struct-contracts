pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@external/traderjoe/IAutoPoolVault.sol";
import "@external/traderjoe/IStrategy.sol";
import "@external/traderjoe/IAPTFarm.sol";
import "@mocks/MockRewarder.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IAutoPoolFEYProduct.sol";
import "@interfaces/IStructPriceOracle.sol";

import "@core/common/StructPriceOracle.sol";
import "@core/yield-sources/AutoPoolYieldSource.sol";

import "../BaseTestSetup.sol";

contract YieldSourceBaseTestSetup is BaseTestSetup {
    /// System under test
    AutoPoolYieldSource internal sut;
    IAutoPoolVault internal autoPoolVault;
    IAutoPoolVault internal autoPoolVault_AVAX_USDC = IAutoPoolVault(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d); // AVAX-USDC Farm
    IAutoPoolVault internal autoPoolVaultWithoutFarm = IAutoPoolVault(0x160Cc83a3f77726A33B685B69bFd0B1DAa06e579); // USDC-USDT Farm
    IAutoPoolVault internal autoPoolVault_WETH_AVAX = IAutoPoolVault(0x6178dE6E552055862CF5c56310763EeC0145688d); //  WETH_AVAX Farm

    address internal autoPoolFactory = 0xA3D87597fDAfC3b8F3AC6B68F90CD1f4c05Fa960;
    IAPTFarm internal aptFarm = IAPTFarm(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C);

    IERC20Metadata internal immutable wavax = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20Metadata internal immutable usdc = IERC20Metadata(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IERC20Metadata internal immutable joe = IERC20Metadata(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    IERC20Metadata internal immutable dai = IERC20Metadata(0xd586E7F844cEa2F87f50152665BCbc2C279D8d70);
    IERC20Metadata internal immutable usdt = IERC20Metadata(0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7);
    IERC20Metadata internal immutable btc = IERC20Metadata(0x152b9d0FdC40C096757F570A51E494bd4b943E50);
    IERC20Metadata internal immutable weth = IERC20Metadata(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);
    IERC20Metadata internal immutable eurc = IERC20Metadata(0xC891EB4cbdEFf6e073e859e987815Ed1505c2ACD);

    AggregatorV3Interface internal avax_usdc_feed = AggregatorV3Interface(0x0A77230d17318075983913bC2145DB16C7366156);
    AggregatorV3Interface internal usdc_usd_feed = AggregatorV3Interface(0xF096872672F44d6EBA71458D74fe67F9a77a23B9);
    AggregatorV3Interface internal joe_usd_feed = AggregatorV3Interface(0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a);
    AggregatorV3Interface internal dai_usd_feed = AggregatorV3Interface(0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300);
    AggregatorV3Interface internal usdt_usd_feed = AggregatorV3Interface(0xEBE676ee90Fe1112671f19b6B7459bC678B67e8a);
    AggregatorV3Interface internal weth_usd_feed = AggregatorV3Interface(0x976B3D034E162d8bD72D6b9C989d545b839003b0);
    AggregatorV3Interface internal btc_usd_feed = AggregatorV3Interface(0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743);
    AggregatorV3Interface internal eurc_usd_feed = AggregatorV3Interface(0x14Dd0643044B4E539051E5925dC591B9db4De5ef);

    StructPriceOracle internal structOracle;

    uint256 public constant DECIMAL_BPS = 10 ** 6;
    uint256 public constant MAX_ITERATIONS = 10;

    event TokensSupplied(uint256 amountAIn, uint256 amountBIn, uint256 autoPoolTokenSharesReceived);
    event RedemptionQueued(address indexed productAddress, uint256 roundId);
    event MaxIterationsUpdated(uint256 _maxIterations);
    event TokensFarmed(uint256 _aptTokensFarmed);
    event RewardsRecompounded(uint256 _reward1, uint256 _reward2, uint256 _harvestedTokenA, uint256 _harvestedTokenB);

    function onSetup() public virtual override {
        AggregatorV3Interface[] memory sources = new AggregatorV3Interface[](8);
        sources[0] = avax_usdc_feed;
        sources[1] = usdc_usd_feed;
        sources[2] = joe_usd_feed;
        sources[3] = dai_usd_feed;
        sources[4] = dai_usd_feed;
        sources[5] = weth_usd_feed;
        sources[6] = btc_usd_feed;
        sources[7] = eurc_usd_feed;

        address[] memory assets = new address[](8);
        assets[0] = address(wavax);
        assets[1] = address(usdc);
        assets[2] = address(joe);
        assets[3] = address(dai);
        assets[4] = address(usdt);
        assets[5] = address(weth);
        assets[6] = address(btc);
        assets[7] = address(eurc);

        structOracle = new StructPriceOracle(assets, sources);

        /// This is required to persist deployments across multiple forks
        vm.makePersistent(address(structOracle));
        vm.makePersistent(address(gac));

        setLabels();

        sut = new AutoPoolYieldSource(autoPoolVault,IGAC(address(gac)), IStructPriceOracle(address(structOracle)));

        vm.clearMockedCalls();
    }

    function setLabels() internal {
        vm.label(mockFactory, "MockFactory");
        vm.label(address(wavax), "wAVAX");
        vm.label(address(usdc), "USDC");
        vm.label(address(sut), "AutoPoolYieldSource");
        vm.label(address(structOracle), "StructPriceOracle");
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    ////////////////////////////////////////////////////////////////*/

    function _simulateSupply(address tokenA, address tokenB, AutoPoolYieldSource _sut, address caller) internal {
        uint256 tokenAToSupply = 10e18;
        uint256 tokenAPrice = _getPrice(tokenA);
        uint256 tokenBRatePerTokenA = ((tokenAPrice * 1e18) / _getPrice(tokenB));
        uint256 tokenBToSupply = (tokenAToSupply * tokenBRatePerTokenA) / 1e18;
        uint256 tokenADecimals = IERC20Metadata(tokenA).decimals();
        uint256 tokenBDecimals = IERC20Metadata(tokenB).decimals();
        uint256 tokenAToSupplyInTokenDecimals = Helpers.weiToTokenDecimals(tokenADecimals, tokenAToSupply);
        uint256 tokenBToSupplyInTokenDecimals = Helpers.weiToTokenDecimals(tokenBDecimals, tokenBToSupply);
        /// This is required as YieldSource contract uses `transferFrom()` for `supplyTokens()`
        deal(tokenA, address(caller), tokenAToSupplyInTokenDecimals);
        deal(tokenB, address(caller), tokenBToSupplyInTokenDecimals);
        vm.startPrank(caller);
        IERC20(tokenA).approve(address(_sut), tokenAToSupplyInTokenDecimals);
        IERC20(tokenB).approve(address(_sut), tokenBToSupplyInTokenDecimals);
        _sut.supplyTokens(tokenAToSupplyInTokenDecimals, tokenBToSupplyInTokenDecimals);
        vm.stopPrank();
    }

    function _getPrice(address _asset) internal view returns (uint256) {
        return structOracle.getAssetPrice(_asset);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    ////////////////////////////////////////////////////////////////*/

    function _simulateExecuteQueuedWithdrawls() internal {
        //   vm.warp(block.timestamp + 1 hours);
        IStrategy strategy = IStrategy(autoPoolVault.getStrategy());
        address defaultOperator = address(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2);
        vm.startPrank(defaultOperator);
        strategy.rebalance(0, 0, 0, 0, 0, 0, new bytes(0));
        vm.stopPrank();
    }
}
