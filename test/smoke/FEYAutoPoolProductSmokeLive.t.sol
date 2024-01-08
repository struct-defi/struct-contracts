pragma solidity 0.8.11;

import "forge-std/src/Test.sol";
import "forge-std/src/Script.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@external/traderjoe/IAutoPoolVault.sol";
import "@external/traderjoe/IStrategy.sol";

import "@interfaces/IAutoPoolFEYProduct.sol";

import "@core/common/StructPriceOracle.sol";
import "@core/common/GlobalAccessControl.sol";
import "@core/products/autopool/FEYAutoPoolProductFactory.sol";

import "@core/common/GlobalAccessControl.sol";

import "@core/yield-sources/AutoPoolYieldSource.sol";
import "@core/libraries/types/DataTypes.sol";

import "../common/fey-factory/autopool/AutoPoolFactoryUser.sol";
import "../common/fey-products/FEYProductUser.sol";

/// Note: This script does the following:
///         - Creates a product from the given factory contract (should be passed as env string)
///         - Runs deposit, invest, claimExcess, removeFundsFromLP, and withdraw methods
/// @dev Can be run using: TJAP_FACTORY=<FACTORY_ADDRESS> forge test --mc FEYAutoPoolProductSmokeTestLive
/// @dev This should be run after the deployment for validation.
contract FEYAutoPoolProductSmokeTestLive is Test {
    /// System under test
    FEYAutoPoolProductFactory internal feyAutoPoolProductFactory;

    IERC20Metadata internal immutable wavax = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20Metadata internal immutable usdc = IERC20Metadata(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);

    IAutoPoolVault internal autoPoolVault = IAutoPoolVault(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d);
    IAPTFarm internal aptFarm = IAPTFarm(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C);

    address internal immutable DEV_ADMIN = 0xe48B5e18Ef29D66228a94543FF70871b8f7d6163;

    StructPriceOracle internal structOracle;
    GlobalAccessControl internal gac;

    function setUp() public {}

    function setLabels() internal {
        vm.label(address(feyAutoPoolProductFactory), "FEYAutoPoolProductFactory");
        vm.label(address(structOracle), "StructOracle");

        vm.label(address(wavax), "wAVAX");
        vm.label(address(usdc), "USDC");
    }

    function testSmoke_feyAutoPoolProduct() public {
        try vm.envAddress("TJAP_FACTORY") {
            feyAutoPoolProductFactory = FEYAutoPoolProductFactory(vm.envAddress("TJAP_FACTORY"));

            vm.createSelectFork(vm.envString("MAINNET_RPC"));

            console.log("Running live smoke tests on AutoPoolFEYFactory: ", address(feyAutoPoolProductFactory));
            console.log("FEYProduct Implementation :", feyAutoPoolProductFactory.feyProductImplementation());

            structOracle = StructPriceOracle(address(feyAutoPoolProductFactory.structPriceOracle()));
            gac = GlobalAccessControl(address(feyAutoPoolProductFactory.gac()));
            setLabels();
        } catch {
            vm.skip(true);
        }

        address seniorTrancheToken = address(wavax);
        address juniorTrancheToken = address(usdc);

        AutoPoolFactoryUser productCreator = new AutoPoolFactoryUser(address(feyAutoPoolProductFactory));

        vm.startPrank(DEV_ADMIN);
        gac.grantRole(gac.WHITELIST_MANAGER(), address(DEV_ADMIN));
        gac.grantRole(gac.WHITELISTED(), address(productCreator));
        gac.grantRole(gac.KEEPER(), address(this));

        vm.stopPrank();

        console.log("Creating product...");

        vm.recordLogs();
        productCreator.createProductAndDeposit(seniorTrancheToken, juniorTrancheToken, DataTypes.Tranche.Senior, 0);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        IAutoPoolFEYProduct feyProduct =
            IAutoPoolFEYProduct(address(uint160(uint256(entries[entries.length - 1].topics[1]))));

        vm.label(address(feyProduct), "FEYProduct");

        console.log("Product created: ", address(feyProduct));

        DataTypes.TrancheConfig memory juniorTrancheConfig = feyProduct.getTrancheConfig(DataTypes.Tranche.Junior);
        DataTypes.TrancheConfig memory seniorTrancheConfig = feyProduct.getTrancheConfig(DataTypes.Tranche.Senior);
        DataTypes.ProductConfig memory productConfig = feyProduct.getProductConfig();

        FEYProductUser feyProductUser = new FEYProductUser(address(feyProduct));

        deal(seniorTrancheToken, address(feyProductUser), seniorTrancheConfig.capacity);
        deal(juniorTrancheToken, address(feyProductUser), juniorTrancheConfig.capacity);
        uint256 seniorTokensToDeposit = 10e18;
        uint256 juniorTokensToDeposit = 10e6;

        feyProductUser.increaseAllowance(address(seniorTrancheToken), seniorTokensToDeposit);
        feyProductUser.increaseAllowance(address(juniorTrancheToken), juniorTokensToDeposit);
        console.log("Trying deposit...");

        feyProductUser.depositToSenior(seniorTokensToDeposit);
        feyProductUser.depositToJunior(juniorTokensToDeposit);

        console.log("Success");

        vm.warp(productConfig.startTimeTranche);

        _simulateOracleRoundData();

        {
            address spTokenAddress = address(feyAutoPoolProductFactory.spTokenAddress());
            console.log("Trying invest()...");

            feyProduct.invest();
            console.log("Success");

            console.log("Trying claimExcess()...");

            feyProductUser.setApprovalForAll(IERC1155(spTokenAddress), address(feyProduct));
            feyProductUser.claimExcess(DataTypes.Tranche.Senior);
            console.log("Success");
        }

        {
            vm.warp(productConfig.endTimeTranche);
            _simulateOracleRoundData();
            console.log("Trying removeFundsFromLP()...");

            feyProduct.removeFundsFromLP();

            console.log("Success");
        }

        {
            _simulateExecuteQueuedWithdrawals();

            (, bytes memory data) = address(feyProduct).staticcall(abi.encodeWithSignature("yieldSource()"));
            AutoPoolYieldSource yieldSource = AutoPoolYieldSource(abi.decode(data, (address)));
            vm.label(address(yieldSource), "YieldSource");
            console.log("Trying redeemTokens()...");

            yieldSource.redeemTokens();
            console.log("Success");
        }
        {
            console.log("Trying withdraw()...");

            feyProductUser.withdraw(DataTypes.Tranche.Senior);
            feyProductUser.withdraw(DataTypes.Tranche.Junior);
            console.log("Success");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    ////////////////////////////////////////////////////////////////*/

    function _simulateOracleRoundData() private {
        AggregatorV3Interface oracleX = AggregatorV3Interface(autoPoolVault.getOracleX());
        AggregatorV3Interface oracleY = AggregatorV3Interface(autoPoolVault.getOracleY());
        /// Mock the chainlink aggregator to return the updatedAt as latest timestamp for the data feeds
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleX.latestRoundData();

        vm.mockCall(
            address(oracleX),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
        );

        (roundId, answer, startedAt, updatedAt, answeredInRound) = oracleY.latestRoundData();
        vm.mockCall(
            address(oracleY),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
        );
    }

    function _simulateExecuteQueuedWithdrawals() private {
        IStrategy strategy = IStrategy(autoPoolVault.getStrategy());
        address defaultOperator = address(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2);
        vm.startPrank(defaultOperator);
        strategy.rebalance(0, 0, 0, 0, 0, 0, new bytes(0));
        vm.stopPrank();
    }

    function _getPrice(address _asset) private view returns (uint256) {
        return structOracle.getAssetPrice(_asset);
    }
}
