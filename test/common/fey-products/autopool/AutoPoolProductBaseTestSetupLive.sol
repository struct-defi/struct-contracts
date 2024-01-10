pragma solidity 0.8.11;

import "forge-std/src/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@core/common/GlobalAccessControl.sol";
import "@core/common/StructPriceOracle.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/tokenization/StructSPToken.sol";
import "@core/yield-sources/AutoPoolYieldSource.sol";
import "@core/yield-sources/LLAutoPoolYieldSource.sol";
import "@core/misc/DistributionManager.sol";

import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/ISPToken.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";
import "@interfaces/IAutoPoolYieldSource.sol";

import "./AutoPoolProductHarness.sol";
import "../FEYProductUser.sol";

contract AutoPoolProductBaseTestSetupLive is Test {
    FEYProductUser internal admin;
    FEYProductUser internal user1;
    FEYProductUser internal user2;
    FEYProductUser internal user3;
    IAutoPoolYieldSource public yieldSource;

    /// Struct specific contracts
    AutoPoolProductHarness internal sut;
    StructPriceOracle public oracle;
    GlobalAccessControl internal gac;
    StructSPToken public spToken;

    address public distributionManager;
    address public factory;
    IDistributionManager.RecipientData[] internal recipients;

    IERC20Metadata internal wavax = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20Metadata internal euroc = IERC20Metadata(0xC891EB4cbdEFf6e073e859e987815Ed1505c2ACD);
    IERC20Metadata internal usdc = IERC20Metadata(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IERC20Metadata internal bbtc = IERC20Metadata(0x152b9d0FdC40C096757F570A51E494bd4b943E50);
    IERC20Metadata internal joe = IERC20Metadata(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);

    IAutoPoolVault internal autoPoolVault = IAutoPoolVault(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d);
    IAutoPoolVault internal autoPoolVault_euroc_usdc = IAutoPoolVault(0x052AF5B8aC73082D8c4C8202bB21F4531A51DC73);

    AggregatorV3Interface internal feed_usdc_avax = AggregatorV3Interface(0x0A77230d17318075983913bC2145DB16C7366156);

    AggregatorV3Interface internal feed_usdc_btc = AggregatorV3Interface(0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743);

    AggregatorV3Interface internal feed_usdc_usdt = AggregatorV3Interface(0xF096872672F44d6EBA71458D74fe67F9a77a23B9);

    AggregatorV3Interface internal feed_usd_joe = AggregatorV3Interface(0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a);

    AggregatorV3Interface internal feed_usd_euro = AggregatorV3Interface(0x192f2DBA961Bb0277520C082d6bfa87D5961333E);

    /// Roles
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant WHITELISTED = keccak256("WHITELISTED");
    bytes32 public constant WHITELIST_MANAGER = keccak256("WHITELIST_MANAGER");
    bytes32 public constant KEEPER = keccak256("KEEPER");

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    DataTypes.Tranche public constant SENIOR_TRANCHE = DataTypes.Tranche.Senior;
    DataTypes.Tranche public constant JUNIOR_TRANCHE = DataTypes.Tranche.Junior;

    uint256 private nonce = 1;
    uint256 internal fixedRate = 50000; // 5%
    uint256 internal managementFee = 0; // 1%
    uint256 internal performanceFee = 1000000; // 1%

    address public productCreatorAddress = getNextAddress();
    address public keeper = getNextAddress();

    function setUp() public virtual {
        onSetup();
        setContractsLabels();
        grantRoles();
    }

    function onSetup() public virtual {}

    function initOracle() internal {
        AggregatorV3Interface[] memory sources = new AggregatorV3Interface[](5);
        sources[0] = feed_usdc_avax;
        sources[1] = feed_usdc_btc;
        sources[2] = feed_usdc_usdt;
        sources[3] = feed_usd_joe;
        sources[4] = feed_usd_euro;

        address[] memory assets = new address[](5);
        assets[0] = address(wavax);
        assets[1] = address(bbtc);
        assets[2] = address(usdc);
        assets[3] = address(joe);
        assets[4] = address(euroc);

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
        gac.grantRole(KEEPER, address(keeper));

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
        vm.label(address(euroc), "EUROC");
        vm.label(address(autoPoolVault), "AutoPoolVault");
        vm.label(address(autoPoolVault_euroc_usdc), "AutoPoolVault EUROC-USDC");
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

    function setupYieldSource(address _tokenSr, address _tokenJr) internal {
        AutoPoolYieldSource _yieldSource;
        if (
            (_tokenSr == address(wavax) && _tokenJr == address(usdc))
                || (_tokenSr == address(usdc) && _tokenJr == address(wavax))
        ) {
            _yieldSource = new AutoPoolYieldSource(
                autoPoolVault,
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle))
            );
        } else if (
            (_tokenSr == address(euroc) && _tokenJr == address(usdc))
                || (_tokenSr == address(usdc) && _tokenJr == address(euroc))
        ) {
            _yieldSource = new LLAutoPoolYieldSource(
                autoPoolVault_euroc_usdc,
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle))
            );
        } else {
            revert("Invalid token pair");
        }
        yieldSource = IAutoPoolYieldSource(address(_yieldSource));
    }

    function investTestsFixture(
        IERC20Metadata _tokenSr,
        IERC20Metadata _tokenJr,
        uint256 _capacitySr,
        uint256 _capacityJr,
        uint256 _termLength
    ) internal {
        console.log("Creating product...");
        console.log("Senior tranche token is %s", IERC20Metadata(address(_tokenSr)).symbol());
        console.log("Junior tranche token is %s", IERC20Metadata(address(_tokenJr)).symbol());

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
            endTimeTranche: block.timestamp + _termLength + 10 minutes,
            leverageThresholdMin: 1250000,
            leverageThresholdMax: 750000,
            managementFee: managementFee,
            performanceFee: performanceFee
        });

        DataTypes.InitConfigParam memory initConfigParams =
            DataTypes.InitConfigParam(trancheConfigSenior, trancheConfigJunior, productConfig);
        sut = new AutoPoolProductHarness();
        setupYieldSource(address(_tokenSr), address(_tokenJr));

        IDistributionManager.RecipientData memory recipient1 =
            IDistributionManager.RecipientData(makeAddr("admin"), 1e18, 0);
        recipients.push(recipient1);
        distributionManager = address(
            new DistributionManager(
                IERC20Metadata(address(wavax)),
                1e15,
                IGAC(address(gac)),
                recipients
            )
        );
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

    /// @dev Used to simulate deposit to the given tranche
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

    /// @dev Used to simulate deposit with AVAX to the given tranche
    function _depositAvax(FEYProductUser _user, uint256 _amountToDeposit, DataTypes.Tranche _tranche) internal {
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        if (_tranche == SENIOR_TRANCHE) {
            /// Using `deal` instead of `mint` helps us share this function with the Fork tests as well
            deal(address(_user), _amountToDeposit);
            _user.depositAvaxToSenior(_amountToDeposit, _amountToDeposit);
        } else {
            deal(address(_user), _amountToDeposit);
            _user.depositAvaxToJunior(_amountToDeposit, _amountToDeposit);
        }
    }

    /// @dev Used to simulate `depositFor()` for the given tranche
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
