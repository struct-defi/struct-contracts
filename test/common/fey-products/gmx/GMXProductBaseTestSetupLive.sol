pragma solidity 0.8.11;

import "forge-std/src/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@core/common/GlobalAccessControl.sol";
import "@core/common/StructPriceOracle.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/tokenization/StructSPToken.sol";

import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/ISPToken.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";
import "@interfaces/IGMXYieldSource.sol";

import "../FEYProductUser.sol";
import "./GMXProductHarness.sol";
import "../../yield-sources/GMXYieldSourceHarness.sol";

contract GMXProductBaseTestSetupLive is Test {
    FEYProductUser internal admin;
    FEYProductUser internal user1;
    FEYProductUser internal user2;
    FEYProductUser internal user3;
    IGMXYieldSource public yieldSource;

    /// Struct specific contracts
    GMXProductHarness internal sut;
    StructPriceOracle public oracle;
    GlobalAccessControl internal gac;
    StructSPToken public spToken;

    address public distributionManager;
    address public factory;

    /// GMX related addresses
    IERC20Metadata public constant FSGLP = IERC20Metadata(0x9e295B5B976a184B14aD8cd72413aD846C299660);
    IGMXRewardRouterV2 public constant GLP_REWARD_ROUTERV2 =
        IGMXRewardRouterV2(0xB70B91CE0771d3f4c81D87660f71Da31d48eB3B3);
    IERC20Metadata internal wavax = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20Metadata internal usdc = IERC20Metadata(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IERC20Metadata internal bbtc = IERC20Metadata(0x152b9d0FdC40C096757F570A51E494bd4b943E50);
    /// bridged btc

    AggregatorV3Interface internal feed_usdc_avax = AggregatorV3Interface(0x0A77230d17318075983913bC2145DB16C7366156);

    AggregatorV3Interface internal feed_usdc_btc = AggregatorV3Interface(0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743);

    AggregatorV3Interface internal feed_usdc_usdt = AggregatorV3Interface(0xF096872672F44d6EBA71458D74fe67F9a77a23B9);

    /// Roles
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant WHITELISTED = keccak256("WHITELISTED");
    bytes32 public constant WHITELIST_MANAGER = keccak256("WHITELIST_MANAGER");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    DataTypes.Tranche public constant SENIOR_TRANCHE = DataTypes.Tranche.Senior;
    DataTypes.Tranche public constant JUNIOR_TRANCHE = DataTypes.Tranche.Junior;

    uint256 private nonce = 1;
    uint256 internal fixedRate = 5000; // 0.05%
    uint256 internal managementFee = 10000; // 1%
    uint256 internal performanceFee = 10000; // 1%

    address public productCreatorAddress = getNextAddress();

    function setUp() public virtual {
        onSetup();
        setContractsLabels();
        grantRoles();
    }

    function onSetup() public virtual {}

    function initOracle() internal {
        AggregatorV3Interface[] memory sources = new AggregatorV3Interface[](3);
        sources[0] = feed_usdc_avax;
        sources[1] = feed_usdc_btc;
        sources[2] = feed_usdc_usdt;

        address[] memory assets = new address[](3);
        assets[0] = address(wavax);
        assets[1] = address(bbtc);
        assets[2] = address(usdc);

        oracle = new StructPriceOracle(assets, sources);
    }

    function grantRoles() internal {
        gac.grantRole(DEFAULT_ADMIN_ROLE, address(admin));
        gac.grantRole(GOVERNANCE, address(admin));

        vm.startPrank(address(admin));
        gac.grantRole(WHITELIST_MANAGER, address(admin));

        gac.grantRole(WHITELISTED, address(user1));
        gac.grantRole(WHITELISTED, address(user2));
        gac.grantRole(WHITELISTED, address(user3));
        gac.grantRole(FACTORY, address(factory));
        gac.grantRole(FACTORY, address(admin));
        gac.grantRole(PRODUCT, address(sut));
        /// This is required for the `depositForTests()`
        gac.grantRole(FACTORY, address(user1));
        gac.grantRole(FACTORY, address(user2));
        vm.stopPrank();
    }

    function setContractsLabels() internal {
        vm.label(address(admin), "Admin");

        vm.label(address(user1), "User 1");
        vm.label(address(user2), "User 2");
        vm.label(address(user3), "User 3");
        vm.label(productCreatorAddress, "ProductCreator");

        vm.label(address(gac), "GAC");
        vm.label(address(this), "BaseSetup Contract");
        vm.label(address(sut), "FEYProduct");
        vm.label(address(oracle), "StructPriceOracle");
        vm.label(address(yieldSource), "YieldSource");

        vm.label(address(wavax), "WAVAX");
        vm.label(address(usdc), "USDC");

        vm.label(address(FSGLP), "FSGLP");
        vm.label(address(GLP_REWARD_ROUTERV2), "GLP_REWARD_ROUTERV2");
    }

    function createUsers(address _feyProductContract) internal {
        admin = new FEYProductUser(_feyProductContract);
        user1 = new FEYProductUser(_feyProductContract);
        user2 = new FEYProductUser(_feyProductContract);
        user3 = new FEYProductUser(_feyProductContract);
    }

    function getNextAddress() internal returns (address) {
        return vm.addr(nonce++);
    }

    function setupYieldSource() internal {
        vm.prank(address(admin));
        GMXYieldSourceHarness _yieldSource = new GMXYieldSourceHarness(factory, address(gac));

        yieldSource = IGMXYieldSource(address(_yieldSource));
    }

    function setGMXProductInfo(IERC20Metadata _tokenSr, IERC20Metadata _tokenJr) internal {
        address tokenA = address(_tokenSr);
        uint8 tokenADecimals = IERC20Metadata(address(_tokenSr)).decimals();
        address tokenB = address(_tokenJr);
        uint8 tokenBDecimals = IERC20Metadata(address(_tokenJr)).decimals();
        uint256 fsGLPReceived = 0;
        uint256 shares = 0;

        DataTypes.FEYGMXProductInfo memory _productInfo = DataTypes.FEYGMXProductInfo({
            tokenA: tokenA,
            tokenB: tokenB,
            tokenADecimals: tokenADecimals,
            tokenBDecimals: tokenBDecimals,
            fsGLPReceived: fsGLPReceived,
            shares: shares,
            sameToken: tokenA == tokenB
        });
        grantRoles();
        vm.prank(address(admin));
        yieldSource.setFEYGMXProductInfo(address(sut), _productInfo);
    }

    function investTestsFixture(
        IERC20Metadata _tokenSr,
        IERC20Metadata _tokenJr,
        uint256 _capacitySr,
        uint256 _capacityJr
    ) internal {
        /// Deploy GAC
        gac = new GlobalAccessControl(address(this));

        /// Mock factory
        factory = vm.addr(0xa);

        /// Deploy StructSPToken
        spToken = new StructSPToken(IGAC(address(gac)), IFEYFactory(factory));

        /// Deploy FEYProduct
        DataTypes.TrancheConfig memory trancheConfigSenior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(address(_tokenSr)),
            decimals: IERC20Metadata(address(_tokenSr)).decimals(),
            spTokenId: 0,
            capacity: _capacitySr
        });

        DataTypes.TrancheConfig memory trancheConfigJunior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(address(_tokenJr)),
            decimals: IERC20Metadata(address(_tokenJr)).decimals(),
            spTokenId: 1,
            capacity: _capacityJr
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
            performanceFee: performanceFee // 1%
        });

        DataTypes.InitConfigParam memory initConfigParams =
            DataTypes.InitConfigParam(trancheConfigSenior, trancheConfigJunior, productConfig);
        sut = new GMXProductHarness();
        setupYieldSource();
        sut.initialize(
            initConfigParams,
            IStructPriceOracle(address(oracle)),
            ISPToken(address(spToken)),
            IGAC(address(gac)),
            IDistributionManager(distributionManager),
            address(yieldSource), // Yield Source
            payable(address(wavax))
        );
        createUsers(address(sut));
    }

    ///@dev Used to simulate deposit to the given tranche
    function _deposit(FEYProductUser _user, uint256 _amountToDeposit, DataTypes.Tranche _tranche, IERC20Metadata _token)
        internal
    {
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        if (_tranche == SENIOR_TRANCHE) {
            /// Using `deal` instead of `mint` helps us share this function with the Fork tests as well
            deal(address(_token), address(_user), _amountToDeposit);
            _user.increaseAllowance(address(_token), _amountToDeposit);
            _user.depositToSenior(_amountToDeposit);
        } else {
            deal(address(_token), address(_user), _amountToDeposit);
            _user.increaseAllowance(address(_token), _amountToDeposit);
            _user.depositToJunior(_amountToDeposit);
        }
    }

    ///@dev Used to simulate `depositFor()` for the given tranche
    function _depositFor(
        FEYProductUser _user,
        uint256 _amountToDeposit,
        DataTypes.Tranche _tranche,
        FEYProductUser _onBehalfOf
    ) internal {
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        if (_tranche == SENIOR_TRANCHE) {
            /// Using `deal` instead of `mint` helps us share this function with the Fork tests as well
            deal(address(wavax), address(_user), _amountToDeposit);
            _user.increaseAllowance(address(wavax), _amountToDeposit);
            _user.depositToSeniorFor(_amountToDeposit, address(_onBehalfOf));
        } else {
            deal(address(usdc), address(_user), _amountToDeposit);
            _user.increaseAllowance(address(usdc), _amountToDeposit);
            _user.depositToJuniorFor(_amountToDeposit, address(_onBehalfOf));
        }
    }
}
