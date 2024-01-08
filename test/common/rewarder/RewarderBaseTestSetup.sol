// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "forge-std/src/Test.sol";
import "@core/common/GlobalAccessControl.sol";
import "@core/misc/Rewarder.sol";
import "@core/tokenization/StructSPToken.sol";

import "@mocks/MockERC20.sol";
import "@mocks/MockWETH.sol";
import "@mocks/MockOracle.sol";

import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/ISPToken.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";

import "../fey-products/FEYProductUser.sol";
import "../fey-products/autopool/AutoPoolProductHarness.sol";
import "./RewarderHarness.sol";

abstract contract RewarderBaseTestSetup is Test {
    FEYProductUser internal admin;
    FEYProductUser internal user1;
    FEYProductUser internal user2;

    uint256 srRewardAPR = 500000;
    uint256 jrRewardAPR = 500000;
    uint256 srInvestable = 1000 * 1e18;
    uint256 jrInvestable = 20000 * 1e18;
    uint256 jrDepositWAD = 20 * 1e18;
    uint256 srDepositWAD = 20 * 1e18;
    uint256 avaxPrice = 20e18;
    uint256 usdcPrice = 1e6;
    uint256 usdcPriceWAD = 1e18;
    uint256 reward2Price = 5e18;

    /// Struct specific contracts
    RewarderHarness public sut;
    AutoPoolProductHarness internal product;
    MockOracle public oracle;
    GlobalAccessControl internal gac;
    address public distributionManager;
    address public factory;
    StructSPToken public spToken;

    // RewarderUser internal rewarder;
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant REWARDER = keccak256("REWARDER");
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// Mock tokens
    MockWETH9 public wavax;
    MockERC20 public usdc;
    MockERC20 public rewardToken2;
    MockERC20 public rewardToken3;

    uint256 private nonce = 1;
    uint256 public constant DURATION = 12 weeks;
    bool internal seniorTrancheIsWAVAX;

    DataTypes.Tranche public constant SENIOR_TRANCHE = DataTypes.Tranche.Senior;
    DataTypes.Tranche public constant JUNIOR_TRANCHE = DataTypes.Tranche.Junior;

    address yieldSource = getNextAddress();
    address autoPoolVault = getNextAddress();
    address internal pauser = getNextAddress();
    address internal rewarder = getNextAddress();

    function setUp() public {
        createTokens();
        onSetup();
        deployRewarder();
        setContractsLabels();
        grantRoles();
    }

    function onSetup() public virtual {}

    function grantRoles() internal {
        gac.grantRole(DEFAULT_ADMIN_ROLE, address(admin));
        gac.grantRole(GOVERNANCE, address(admin));

        vm.startPrank(address(admin));
        gac.grantRole(FACTORY, address(factory));
        gac.grantRole(FACTORY, address(admin));
        gac.grantRole(FACTORY, address(this));
        gac.grantRole(PRODUCT, address(product));
        gac.grantRole(PAUSER, address(pauser));

        ///Need to initialize new role for rewarder
        gac.initializeNewRole(REWARDER, "REWARDER", GOVERNANCE);
        gac.grantRole(REWARDER, rewarder);
        vm.stopPrank();
    }

    function createTokens() internal {
        wavax = new MockWETH9();
        usdc = new MockERC20("USDC", "USDC", 6);
        rewardToken2 = new MockERC20("REWARD2", "REWARD2", 18);
        rewardToken3 = new MockERC20("REWARD3", "REWARD3", 18);
    }

    function getNextAddress() internal returns (address) {
        return vm.addr(nonce++);
    }

    function setContractsLabels() internal {
        vm.label(address(user1), "User 1");
        vm.label(address(user2), "User 2");
        vm.label(address(admin), "Admin");
        vm.label(address(pauser), "Pauser");

        vm.label(address(gac), "GAC");
        vm.label(address(factory), "Factory");
        vm.label(address(this), "Setup Contract");
        vm.label(address(sut), "Rewarder");

        vm.label(address(wavax), "WAVAX");
        vm.label(address(usdc), "USDC");
        vm.label(address(rewardToken2), "REWARD2");
        vm.label(address(rewardToken3), "REWARD3");
    }

    function createUsers(address _feyProductContract) internal {
        user1 = new FEYProductUser(_feyProductContract);
        user2 = new FEYProductUser(_feyProductContract);
        admin = new FEYProductUser(_feyProductContract);
    }

    function depositInvestTestsFixture(bool seniorIsWAVAX) internal {
        seniorTrancheIsWAVAX = seniorIsWAVAX;

        /// Make sure all mocked calls are clears before running a test
        vm.clearMockedCalls();

        /// Deploy oracle
        oracle = new MockOracle();

        /// Set asset price (mock)
        oracle.setAssetPrice(address(wavax), 20e18);
        oracle.setAssetPrice(address(usdc), 1e18);
        oracle.setAssetPrice(address(rewardToken2), 5e18);

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
            endTimeTranche: block.timestamp + 10 minutes + DURATION,
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

        product = new AutoPoolProductHarness();

        product.initialize(
            initConfigParams,
            IStructPriceOracle(address(oracle)),
            ISPToken(address(spToken)),
            IGAC(address(gac)),
            IDistributionManager(distributionManager),
            address(yieldSource), // Yield Source
            payable(address(wavax))
        );
        createUsers(address(product));
    }

    function deployRewarder() internal {
        sut = new RewarderHarness(
            IGAC(address(gac)),
            IStructPriceOracle(address(oracle))
        );
    }

    ///@dev Used to simulate deposit to the given tranche
    function _deposit(FEYProductUser _user, uint256 _amountToDeposit, DataTypes.Tranche _tranche) internal {
        vm.mockCall(factory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
        address seniorToken;
        address juniorToken;

        if (seniorTrancheIsWAVAX) {
            seniorToken = address(wavax);
            juniorToken = address(usdc);
        } else {
            juniorToken = address(wavax);
            seniorToken = address(usdc);
        }

        if (_tranche == SENIOR_TRANCHE) {
            deal(seniorToken, address(_user), _amountToDeposit);
            _user.increaseAllowance(seniorToken, _amountToDeposit);
            _user.depositToSenior(_amountToDeposit);
        } else {
            deal(juniorToken, address(_user), _amountToDeposit);
            _user.increaseAllowance(juniorToken, _amountToDeposit);
            _user.depositToJunior(_amountToDeposit);
        }
    }

    function handleTransferSpToken(
        uint256 _spTokenTransferAmount,
        address _from,
        address _to,
        DataTypes.Tranche _tranche
    ) internal virtual {
        console.log(
            "User %s transferring %s SP tokens to user %s",
            address(_from),
            _spTokenTransferAmount / Constants.WAD,
            address(_to)
        );
        user1.setApprovalForAll(IERC1155(address(spToken)), address(_to));
        vm.mockCall(address(factory), abi.encodeWithSelector(IFEYFactory.isTransferEnabled.selector), abi.encode(true));
        vm.prank(address(_to));
        spToken.safeTransferFrom(address(_from), address(_to), uint256(_tranche), _spTokenTransferAmount, "");
    }
}
