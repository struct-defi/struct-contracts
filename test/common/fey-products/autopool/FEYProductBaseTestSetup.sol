pragma solidity 0.8.11;

import "forge-std/src/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@mocks/MockERC20.sol";
import "@mocks/MockWETH.sol";
import "@core/common/GlobalAccessControl.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/products/autopool/FEYAutoPoolProduct.sol";
import "@core/tokenization/StructSPToken.sol";

import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/ISPToken.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";

import "@mocks/MockOracle.sol";

import "../FEYProductUser.sol";
import "./AutoPoolProductHarness.sol";

abstract contract FEYProductBaseTestSetup is Test {
    FEYProductUser internal admin;
    FEYProductUser internal user1;
    FEYProductUser internal user2;
    FEYProductUser internal user3;
    FEYProductUser internal pauser;

    /// Struct specific contracts
    AutoPoolProductHarness internal sut;
    MockOracle public oracle;
    GlobalAccessControl internal gac;
    StructSPToken public spToken;
    address public distributionManager;
    address public factory;

    /// Roles
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant WHITELISTED = keccak256("WHITELISTED");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant WHITELIST_MANAGER = keccak256("WHITELIST_MANAGER");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// Mock tokens
    MockWETH9 public wavax;
    MockERC20 public usdc;

    DataTypes.Tranche public constant SENIOR_TRANCHE = DataTypes.Tranche.Senior;
    DataTypes.Tranche public constant JUNIOR_TRANCHE = DataTypes.Tranche.Junior;

    uint256 private nonce = 1;
    bool internal seniorTrancheIsWAVAX = true;

    address yieldSource = getNextAddress();
    address autoPoolVault = getNextAddress();

    function setUp() public virtual {
        createTokens();
        onSetup();
        setContractsLabels();
        grantRoles();
    }

    function onSetup() public virtual {}

    function grantRoles() internal {
        gac.grantRole(DEFAULT_ADMIN_ROLE, address(admin));
        gac.grantRole(GOVERNANCE, address(admin));

        vm.startPrank(address(admin));
        gac.grantRole(WHITELIST_MANAGER, address(admin));

        gac.grantRole(WHITELISTED, address(user1));
        gac.grantRole(WHITELISTED, address(user2));
        gac.grantRole(WHITELISTED, address(user3));
        gac.grantRole(PAUSER, address(pauser));
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
        vm.label(address(pauser), "Pauser");

        vm.label(address(gac), "GAC");
        vm.label(address(this), "BaseSetup Contract");
        vm.label(address(sut), "FEYProduct");

        vm.label(address(wavax), "WAVAX");
        vm.label(address(usdc), "USDC");
    }

    function createUsers(address _feyProductContract) internal {
        admin = new FEYProductUser(_feyProductContract);
        user1 = new FEYProductUser(_feyProductContract);
        user2 = new FEYProductUser(_feyProductContract);
        user3 = new FEYProductUser(_feyProductContract);
        pauser = new FEYProductUser(_feyProductContract);
    }

    function createTokens() internal {
        wavax = new MockWETH9();
        usdc = new MockERC20("USDC", "USDC", 6);
    }

    function getNextAddress() internal returns (address) {
        return vm.addr(nonce++);
    }

    function depositInvestTestsFixture(bool seniorIsWAVAX) internal {
        /// Make sure all mocked calls are clears before running a test
        vm.clearMockedCalls();

        /// Deploy oracle
        oracle = new MockOracle();

        /// Set asset price (mock)
        oracle.setAssetPrice(address(wavax), 20e18);
        oracle.setAssetPrice(address(usdc), 1e18);

        /// Deploy GAC
        gac = new GlobalAccessControl(address(this));

        /// Mock factory
        factory = vm.addr(0xa);

        /// Deploy StructSPToken
        spToken = new StructSPToken(IGAC(address(gac)), IFEYFactory(factory));

        /// Deploy FEYProduct
        DataTypes.TrancheConfig memory trancheConfigSenior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(payable(address(wavax))),
            decimals: 18,
            spTokenId: 0,
            capacity: 1000e18
        });

        DataTypes.TrancheConfig memory trancheConfigJunior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(address(usdc)),
            decimals: 6,
            spTokenId: 1,
            capacity: 20000e18
        });

        DataTypes.ProductConfig memory productConfig = DataTypes.ProductConfig({
            poolId: 0,
            fixedRate: 5000,
            startTimeDeposit: block.timestamp,
            startTimeTranche: block.timestamp + 10 minutes,
            endTimeTranche: block.timestamp + 30 minutes,
            leverageThresholdMin: 125000,
            leverageThresholdMax: 75000,
            managementFee: 0,
            performanceFee: 0
        });

        DataTypes.InitConfigParam memory initConfigParams = DataTypes.InitConfigParam(
            seniorIsWAVAX ? trancheConfigSenior : trancheConfigJunior,
            seniorIsWAVAX ? trancheConfigJunior : trancheConfigSenior,
            productConfig
        );
        sut = new AutoPoolProductHarness();
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

        /// autoPoolVault() selector =>  0xb9417a7f
        vm.mockCall(address(yieldSource), abi.encodeWithSelector(0xb9417a7f), abi.encode(autoPoolVault));

        /// IAutoPoolVault.isDepositsPaused.selector => 0x27042b84
        vm.mockCall(address(autoPoolVault), abi.encodeWithSelector(0x27042b84), abi.encode(false));
    }

    ///@dev Used to simulate deposit to the given tranche
    function _deposit(FEYProductUser _user, uint256 _amountToDeposit, DataTypes.Tranche _tranche) internal {
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        if (_tranche == SENIOR_TRANCHE) {
            deal(address(wavax), address(_user), _amountToDeposit);
            _user.increaseAllowance(address(wavax), _amountToDeposit);
            _user.depositToSenior(_amountToDeposit);
        } else {
            deal(address(usdc), address(_user), _amountToDeposit);
            _user.increaseAllowance(address(usdc), _amountToDeposit);
            _user.depositToJunior(_amountToDeposit);
        }
    }
}
