// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console
pragma solidity 0.8.11;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/common/GlobalAccessControl.sol";
import "@core/common/StructPriceOracle.sol";
import "@core/tokenization/StructSPToken.sol";
import "@core/products/autopool/FEYAutoPoolProduct.sol";
import "@core/products/autopool/FEYAutoPoolProductFactory.sol";
import "@core/yield-sources/AutoPoolYieldSource.sol";
import "@core/yield-sources/LLAutoPoolYieldSource.sol";

import "@core/misc/DistributionManager.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/IFEYFactory.sol";
import {AddressesDevelop} from "../../../deployment-helpers/develop/AddressesDevelop.sol";
import {ConfigDevelop} from "../../../deployment-helpers/develop/ConfigDevelop.sol";
import "../../BaseDeployer.s.sol";
import "@core/misc/Rewarder.sol";
import "@core/lens/FEYAutoPoolProductLens.sol";

contract DeployAutoPoolProductAndFactoryDevelop is ConfigDevelop, AddressesDevelop, BaseDeployer {
    function run() external {
        console.log("Starting deployment of the Autopools contracts for DEVELOP");
        vm.startBroadcast(deployerPrivateKey);

        StructPriceOracle oracle;
        if (STRUCT_PRICE_ORACLE == address(0)) {
            console.log("About to deploy the Oracle contract");

            AggregatorV3Interface[] memory sources = new AggregatorV3Interface[](3);
            sources[0] = AggregatorV3Interface(PRICE_FEED_AVAX);
            sources[1] = AggregatorV3Interface(PRICE_FEED_USDC);
            sources[2] = AggregatorV3Interface(PRICE_FEED_JOE);

            address[] memory assets = new address[](3);
            assets[0] = WAVAX;
            assets[1] = USDC;
            assets[2] = JOE;

            oracle = new StructPriceOracle(assets, sources);

            address oracleAddress = address(oracle);
            console.log("Deployment of Struct Price Oracle success: %", oracleAddress);
        } else {
            console.log("NOT deploying the Oracle contract");
            oracle = StructPriceOracle(STRUCT_PRICE_ORACLE);
        }

        GlobalAccessControl gac;
        if (address(GAC) == address(0)) {
            console.log("About to deploy the GAC contract");
            gac = new GlobalAccessControl(deployerAddress);

            address gacAddress = address(gac);
            console.log("Deployment of GAC success: %", gacAddress);
        } else {
            console.log("Not deploying the GAC contract");
            gac = GlobalAccessControl(GAC);
        }

        StructSPToken spToken;
        if (address(STRUCT_SP_TOKEN) == address(0)) {
            console.log("About to deploy the StructSPToken contract");
            spToken = new StructSPToken(
                IGAC(address(gac)),
                IFEYFactory(address(0))
            );

            address spTokenAddress = address(spToken);
            console.log("Deployment of spToken success: %", spTokenAddress);
        } else {
            console.log("Not deploying the spToken contract");
            spToken = StructSPToken(STRUCT_SP_TOKEN);
        }

        /// DistributionManager
        DistributionManager distributionManager;
        if (STRUCT_DISTRIBUTION_MANAGER == address(0)) {
            console.log("About to deploy the DistributionManager contract");
            IDistributionManager.RecipientData memory recipient1 =
                IDistributionManager.RecipientData(deployerAddress, allocationPoints, allocationFee);
            recipients.push(recipient1);
            distributionManager = new DistributionManager(
                IERC20Metadata(address(WAVAX)),
                rewardsPerSecond,
                IGAC(address(gac)),
                recipients
            );

            address distributionManagerAddress = address(distributionManager);
            console.log("Deployment of DistributionManager success: %", distributionManagerAddress);
        } else {
            console.log("Not deploying the DistributionManager contract");
            distributionManager = DistributionManager(STRUCT_DISTRIBUTION_MANAGER);
        }

        /// Product
        FEYAutoPoolProduct feyAutoPoolProductImplementation;
        if (AUTOPOOL_PRODUCT_IMPLEMENTATION == address(0)) {
            console.log("About to deploy the Product contract");
            DataTypes.TrancheConfig memory trancheConfigSenior = DataTypes.TrancheConfig({
                tokenAddress: IERC20Metadata(address(0)),
                decimals: 0,
                spTokenId: 0,
                capacity: 0
            });

            DataTypes.TrancheConfig memory trancheConfigJunior = DataTypes.TrancheConfig({
                tokenAddress: IERC20Metadata(address(0)),
                decimals: 0,
                spTokenId: 0,
                capacity: 0
            });

            DataTypes.ProductConfig memory productConfig = DataTypes.ProductConfig({
                poolId: 0,
                fixedRate: 0,
                startTimeDeposit: 0,
                startTimeTranche: 0,
                endTimeTranche: 0,
                leverageThresholdMin: 0,
                leverageThresholdMax: 0,
                managementFee: 0,
                performanceFee: 0
            });

            DataTypes.InitConfigParam memory initConfigParams =
                DataTypes.InitConfigParam(trancheConfigSenior, trancheConfigJunior, productConfig);

            feyAutoPoolProductImplementation = new FEYAutoPoolProduct();

            console.log("About to initialize the Product contract");
            feyAutoPoolProductImplementation.initialize(
                initConfigParams,
                IStructPriceOracle(STRUCT_PRICE_ORACLE),
                ISPToken(address(spToken)),
                IGAC(address(gac)),
                IDistributionManager(address(distributionManager)),
                address(0), // Yield Source
                payable(address(WAVAX))
            );

            address feyAutoPoolProductAddress = address(feyAutoPoolProductImplementation);
            console.log("Deployment of FeyAutoPoolProduct success: %", feyAutoPoolProductAddress);
        } else {
            console.log("Not deploying the product implementation contract");
            feyAutoPoolProductImplementation = FEYAutoPoolProduct(AUTOPOOL_PRODUCT_IMPLEMENTATION);
        }

        /// Factory
        FEYAutoPoolProductFactory feyAutoPoolProductFactory;
        if (AUTOPOOL_FACTORY == address(0)) {
            console.log("About to deploy the Factory contract");
            feyAutoPoolProductFactory = new FEYAutoPoolProductFactory(
                ISPToken(address(spToken)),
                address(feyAutoPoolProductImplementation),
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle)),
                IERC20Metadata(address(WAVAX)),
                IDistributionManager(address(distributionManager))
            );
            console.log("Setting the product implementation address on the factory");
            feyAutoPoolProductFactory.setFEYProductImplementation(address(feyAutoPoolProductImplementation));

            address feyAutoPoolProductFactoryAddress = address(feyAutoPoolProductFactory);
            console.log("Deployment of FeyAutopoolProductFactory success: %", feyAutoPoolProductFactoryAddress);
        } else {
            console.log("Not deploying the Factory contract");
            feyAutoPoolProductFactory = FEYAutoPoolProductFactory(AUTOPOOL_FACTORY);
            // new product implementation was deployed
            if (address(feyAutoPoolProductImplementation) != AUTOPOOL_PRODUCT_IMPLEMENTATION) {
                console.log("Setting the product implementation address on the factory");
                feyAutoPoolProductFactory.setFEYProductImplementation(address(feyAutoPoolProductImplementation));
            }
        }

        console.log("About to grant GOVERNANCE to the deployer account");
        gac.grantRole(GOVERNANCE, deployerAddress);

        console.log("About to grant WHITELIST_MANAGER to the deployer account");
        gac.grantRole(WHITELIST_MANAGER, deployerAddress);

        console.log("About to grant FACTORY role to the factory");
        gac.grantRole(FACTORY, address(feyAutoPoolProductFactory));

        console.log("Setting the deployed factory to the spToken");
        spToken.setFeyProductFactory(IFEYFactory(address(feyAutoPoolProductFactory)));

        if (AVAX_USDC_AUTOPOOL_YIELDSOURCE == address(0)) {
            console.log("About to deploy the AVAX/USDC autovault's yield source");
            AutoPoolYieldSource autopoolYieldSourceAvaxUsdc = new AutoPoolYieldSource(
                IAutoPoolVault(AVAX_USDC_AUTOVAULT),
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle))
            );

            address yieldSourceAddressAvaxUsdc = address(autopoolYieldSourceAvaxUsdc);
            console.log("Deployment of AVAX/USDC YieldSource success: %", yieldSourceAddressAvaxUsdc);

            feyAutoPoolProductFactory.setYieldSource(AVAX_USDC_AUTOVAULT, yieldSourceAddressAvaxUsdc);

            emit Deployed("AutoPool", "TJAP AVAX/USDC Yield Source");
        } else {
            console.log("Not deploying the AVAX/USDC yield source contract");
            console.log("Setting AVAX/USDC yield source address as % on factory", AVAX_USDC_AUTOPOOL_YIELDSOURCE);
            feyAutoPoolProductFactory.setYieldSource(AVAX_USDC_AUTOVAULT, AVAX_USDC_AUTOPOOL_YIELDSOURCE);
        }

        if (AVAX_BTCB_AUTOPOOL_YIELDSOURCE == address(0)) {
            console.log("About to deploy the AVAX/BTC.b autovault's yield source");
            AutoPoolYieldSource autopoolYieldSourceAvaxBtcb = new AutoPoolYieldSource(
                IAutoPoolVault(AVAX_BTCB_AUTOVAULT),
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle))
            );

            address yieldSourceAddressAvaxBtcb = address(autopoolYieldSourceAvaxBtcb);
            console.log("Deployment of TJAP AVAX/BTC.b Yield Source success: %", yieldSourceAddressAvaxBtcb);

            feyAutoPoolProductFactory.setYieldSource(AVAX_BTCB_AUTOVAULT, yieldSourceAddressAvaxBtcb);

            emit Deployed("AutoPool", "TJAP AVAX/BTC.b Yield Source");
        } else {
            console.log("Not deploying the yield source contract");
            console.log("Setting AVAX/BTC,b yield source address as % on factory", AVAX_BTCB_AUTOPOOL_YIELDSOURCE);
            feyAutoPoolProductFactory.setYieldSource(AVAX_BTCB_AUTOVAULT, AVAX_BTCB_AUTOPOOL_YIELDSOURCE);
        }

        if (AVAX_WETHE_AUTOPOOL_YIELDSOURCE == address(0)) {
            console.log("About to deploy the AVAX/wETH.e autovault's yield source");
            AutoPoolYieldSource autopoolYieldSourceAvaxWeth = new AutoPoolYieldSource(
                IAutoPoolVault(AVAX_WETHE_AUTOVAULT),
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle))
            );

            address yieldSourceAddressAvaxWeth = address(autopoolYieldSourceAvaxWeth);
            console.log("Deployment of TJAP AVAX/wETH.e Yield Source success: %", yieldSourceAddressAvaxWeth);

            feyAutoPoolProductFactory.setYieldSource(AVAX_WETHE_AUTOVAULT, yieldSourceAddressAvaxWeth);

            emit Deployed("AutoPool", "TJAP AVAX/wETH.e Yield Source");
        } else {
            console.log("Not deploying the AVAX/wETH.e yield source contract");
            console.log("Setting AVAX/wETH.e yield source address as % on factory", AVAX_WETHE_AUTOPOOL_YIELDSOURCE);
            feyAutoPoolProductFactory.setYieldSource(AVAX_WETHE_AUTOVAULT, AVAX_WETHE_AUTOPOOL_YIELDSOURCE);
        }

        if (EUROC_USDC_AUTOPOOL_YIELDSOURCE == address(0)) {
            console.log("About to deploy the EURO.c/USDC autovault's yield source");
            AutoPoolYieldSource autopoolYieldSourceEurocUsdc = new LLAutoPoolYieldSource(
                IAutoPoolVault(EUROC_USDC_AUTOVAULT),
                IGAC(address(gac)),
                IStructPriceOracle(address(oracle))
            );

            address yieldSourceAddressEurocUsdc = address(autopoolYieldSourceEurocUsdc);
            console.log("Deployment of TJAP EURO.c/USDC Yield Source success: %", yieldSourceAddressEurocUsdc);

            feyAutoPoolProductFactory.setYieldSource(EUROC_USDC_AUTOVAULT, yieldSourceAddressEurocUsdc);

            emit Deployed("AutoPool", "TJAP EURO.c/USDC Yield Source");
        } else {
            console.log("Not deploying the EURO.c/USDC yield source contract");
            console.log("Setting EURO.c/USDC yield source address as % on factory", EUROC_USDC_AUTOPOOL_YIELDSOURCE);
            feyAutoPoolProductFactory.setYieldSource(EUROC_USDC_AUTOVAULT, EUROC_USDC_AUTOPOOL_YIELDSOURCE);
        }

        console.log("Enabling AVAX token");
        feyAutoPoolProductFactory.setTokenStatus(WAVAX, 1);

        console.log("Enabling USDC token");
        feyAutoPoolProductFactory.setTokenStatus(USDC, 1);

        console.log("Enabling BTC.b token");
        feyAutoPoolProductFactory.setTokenStatus(BTCB, 1);

        console.log("Enabling wETH.e token");
        feyAutoPoolProductFactory.setTokenStatus(WETHE, 1);

        console.log("Enabling EURO.c token");
        feyAutoPoolProductFactory.setTokenStatus(EUROC, 1);

        console.log("Enabling AVAX/USDC autopool");
        feyAutoPoolProductFactory.setPoolStatus(AVAX_USDC_AUTOVAULT, 1);

        console.log("Enabling AVAX/BTC.b autopool");
        feyAutoPoolProductFactory.setPoolStatus(AVAX_BTCB_AUTOVAULT, 1);

        console.log("Enabling AVAX/WETHE autopool");
        feyAutoPoolProductFactory.setPoolStatus(AVAX_WETHE_AUTOVAULT, 1);

        console.log("Enabling EURO.c/USDC autopool");
        feyAutoPoolProductFactory.setPoolStatus(EUROC_USDC_AUTOVAULT, 1);

        console.log("Setting min tranche duration 1 minute");
        feyAutoPoolProductFactory.setMinimumTrancheDuration(60);

        console.log("Setting min deposit value USD to 0.5 cents");
        feyAutoPoolProductFactory.setMinimumDepositValueUSD(5e15);

        console.log("Deployer is not NOT renouncing any roles");
        console.log("For develop deployed contract, the deployer is keeping its privileges");

        /// Rewarder
        if (STRUCT_REWARDER == address(0)) {
            console.log("About to deploy the Rewarder contract");
            Rewarder rewarder = new Rewarder(IGAC(address(gac)), IStructPriceOracle(address(oracle)));
            console.log("Deployment of Rewarder successful: ", address(rewarder));
        } else {
            console.log("NOT deploying the Rewarder contract");
        }

        /// Lens
        if (STRUCT_LENS == address(0)) {
            console.log("About to deploy the Lens contract");
            FEYAutoPoolProductLens lens = new FEYAutoPoolProductLens();
            console.log("Deployment of FEYAutoPoolProductLens success: ", address(lens));
        } else {
            console.log("NOT deploying the Lens contract");
        }

        emit Deployed("AutoPool", "TJAP contracts");

        vm.stopBroadcast();
    }
}
