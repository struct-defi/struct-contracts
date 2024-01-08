// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "forge-std/src/Test.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@core/common/GlobalAccessControl.sol";
import "@mocks/MockERC20.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/yield-sources/AutoPoolYieldSource.sol";
import "./FEYFactoryHarness.sol";
import "@core/tokenization/StructSPToken.sol";
import "@mocks/MockWETH.sol";
import "@external/IWETH9.sol";
import {IAPTFarm, IRewarder} from "@external/traderjoe/IAPTFarm.sol";

import "@interfaces/IStructPriceOracle.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/ISPToken.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";

import "@mocks/MockOracle.sol";

import "./AutoPoolFactoryUser.sol";
import "../../fey-products/FEYProductHarness.sol";

abstract contract FEYFactoryBaseTestSetup is Test {
    AutoPoolFactoryUser internal admin;
    AutoPoolFactoryUser internal user1;
    AutoPoolFactoryUser internal user2;
    AutoPoolFactoryUser internal user3;
    AutoPoolFactoryUser internal pauser;

    /// Struct specific contracts
    FEYFactoryHarness internal sut;
    MockOracle public oracle;
    GlobalAccessControl internal gac;
    StructSPToken public spToken;
    AutoPoolYieldSource public yieldSource;
    // set distributionManager to non-zero address
    address public distributionManager = vm.addr(0xa);
    IAutoPoolVault internal autoPoolVault = IAutoPoolVault(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d);

    FEYProductHarness public productImpl;
    address public validationLib;

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

    uint256 internal constant PRICE_WAVAX = 20e18;
    uint256 internal constant PRICE_USDC = 1e18;
    address internal constant APT_FARM = 0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C;

    DataTypes.Tranche public constant SENIOR_TRANCHE = DataTypes.Tranche.Senior;
    DataTypes.Tranche public constant JUNIOR_TRANCHE = DataTypes.Tranche.Junior;

    uint256 private nonce = 1;

    function setUp() public virtual {
        createTokens();
        onSetup();
        setContractsLabels();
        grantRoles();
    }

    function onSetup() public virtual {}

    function createTokens() internal {
        wavax = new MockWETH9();
        usdc = new MockERC20("USDC", "USDC", 6);
    }

    function grantRoles() internal {
        gac.grantRole(DEFAULT_ADMIN_ROLE, address(admin));
        gac.grantRole(GOVERNANCE, address(admin));
        gac.grantRole(WHITELIST_MANAGER, address(admin));

        vm.startPrank(address(admin));

        gac.grantRole(DEFAULT_ADMIN_ROLE, address(sut));
        gac.grantRole(FACTORY, address(sut));
        gac.grantRole(GOVERNANCE, address(sut));

        gac.grantRole(WHITELISTED, address(user1));
        gac.grantRole(WHITELISTED, address(user2));
        gac.grantRole(PAUSER, address(pauser));

        vm.stopPrank();
    }

    function setContractsLabels() internal {
        vm.label(address(admin), "Admin");

        vm.label(address(user1), "User 1");
        vm.label(address(user2), "User 2");
        vm.label(address(user3), "User 3");

        vm.label(address(gac), "GAC");
        vm.label(address(yieldSource), "YieldSource");
        vm.label(address(this), "BaseSetup Contract");
        vm.label(address(sut), "FEYFactory");

        vm.label(address(wavax), "WAVAX");
        vm.label(address(usdc), "USDC");
    }

    function createUsers(address _feyFactoryContract) internal {
        admin = new AutoPoolFactoryUser(_feyFactoryContract);
        user1 = new AutoPoolFactoryUser(_feyFactoryContract);
        user2 = new AutoPoolFactoryUser(_feyFactoryContract);
        user3 = new AutoPoolFactoryUser(_feyFactoryContract);
        pauser = new AutoPoolFactoryUser(_feyFactoryContract);
    }

    function getNextAddress() internal returns (address) {
        return vm.addr(nonce++);
    }

    function factoryTestsFixture() internal {
        initFactory();
        createUsers(address(sut));
    }

    function initFactory() internal {
        /// Make sure all mocked calls are clears before running a test
        vm.clearMockedCalls();

        /// Deploy oracle
        oracle = new MockOracle();

        /// Set asset price (mock)
        oracle.setAssetPrice(address(wavax), PRICE_WAVAX);
        oracle.setAssetPrice(address(usdc), PRICE_USDC);

        /// Deploy GAC
        gac = new GlobalAccessControl(address(this));

        /// Deploy StructSPToken
        spToken = new StructSPToken(IGAC(address(gac)), IFEYFactory(vm.addr(0xa)));

        /// Mock product implementation
        productImpl = initProductContract();

        sut = new FEYFactoryHarness(
            ISPToken(address(spToken)),
            address(productImpl),
            IGAC(address(gac)),
            IStructPriceOracle(address(oracle)),
            IERC20Metadata(address(wavax)),
            IDistributionManager(distributionManager)
        );
        vm.mockCall(
            address(autoPoolVault),
            abi.encodeWithSelector(IAutoPoolVault.getTokenX.selector),
            abi.encode(address(wavax))
        );
        vm.mockCall(
            address(autoPoolVault), abi.encodeWithSelector(IAutoPoolVault.getTokenY.selector), abi.encode(address(usdc))
        );

        vm.mockCall(address(autoPoolVault), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(12));

        vm.mockCall(address(APT_FARM), abi.encodeWithSelector(IAPTFarm.vaultFarmId.selector), abi.encode(0));

        IAPTFarm.FarmInfo memory _farmInfo = IAPTFarm.FarmInfo(
            IERC20(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d),
            13602996785183687529309514525636914715470,
            1691502560,
            12400793000000000,
            IRewarder(0x0000000000000000000000000000000000000000)
        );
        vm.mockCall(address(APT_FARM), abi.encodeWithSelector(IAPTFarm.farmInfo.selector), abi.encode(_farmInfo));

        vm.mockCall(
            address(APT_FARM),
            abi.encodeWithSelector(IAPTFarm.hasFarm.selector, address(autoPoolVault)),
            abi.encode(true)
        );
        /// Deploy Yield Source
        yieldSource = new AutoPoolYieldSource(autoPoolVault, IGAC(address(gac)), IStructPriceOracle(address(oracle)));
    }

    function setupFactoryState() internal {
        // set factory address in SP Token contract
        spToken.setFeyProductFactory(sut);
        sut.setTokenStatus(address(wavax), 1);
        sut.setTokenStatus(address(usdc), 1);
        sut.setPoolStatus(address(autoPoolVault), 1);
        vm.prank(address(admin));
        sut.setYieldSource(address(autoPoolVault), address(yieldSource));
    }

    function initProductContract() internal returns (FEYProductHarness) {
        /// Deploy FEYProduct
        DataTypes.TrancheConfig memory trancheConfigSenior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(payable(address(wavax))),
            decimals: 18,
            spTokenId: 0,
            capacity: 2000000e18
        });

        DataTypes.TrancheConfig memory trancheConfigJunior = DataTypes.TrancheConfig({
            tokenAddress: IERC20Metadata(address(usdc)),
            decimals: 6,
            spTokenId: 1,
            capacity: 2000000e18
        });

        DataTypes.ProductConfig memory productConfig = DataTypes.ProductConfig({
            poolId: 0,
            fixedRate: 5000,
            startTimeDeposit: block.timestamp,
            startTimeTranche: block.timestamp + 10 minutes,
            endTimeTranche: block.timestamp + 30 minutes,
            leverageThresholdMin: 1000000,
            leverageThresholdMax: 1000000,
            managementFee: 0,
            performanceFee: 0
        });

        DataTypes.InitConfigParam memory initConfigParams =
            DataTypes.InitConfigParam(trancheConfigSenior, trancheConfigJunior, productConfig);
        productImpl = new FEYProductHarness();
        productImpl.initialize(
            initConfigParams,
            IStructPriceOracle(address(oracle)),
            ISPToken(address(spToken)),
            IGAC(address(gac)),
            IDistributionManager(distributionManager),
            address(yieldSource), // Yield Source
            payable(address(wavax)) // Native Token
        );
        return productImpl;
    }
}
