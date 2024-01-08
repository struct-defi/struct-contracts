// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "forge-std/src/Script.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@core/libraries/types/DataTypes.sol";
import "@core/common/GlobalAccessControl.sol";
import "@core/common/StructPriceOracle.sol";
import "@core/tokenization/StructSPToken.sol";
import "@core/products/gmx/FEYGMXProduct.sol";
import "@core/products/gmx/FEYGMXProductFactory.sol";
import "@core/misc/DistributionManager.sol";
import "@core/yield-sources/GMXYieldSource.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IDistributionManager.sol";
import "@interfaces/IFEYFactory.sol";
import {ConfigDevelop} from "../../deployment-helpers/develop/ConfigDevelop.sol";

contract DeployGMXProductAndFactory is Script, ConfigDevelop {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        if (STRUCT_PRICE_ORACLE == address(0)) {
            /// Deploy oracle
            AggregatorV3Interface[] memory sources = new AggregatorV3Interface[](2);
            sources[0] = AggregatorV3Interface(PRICE_FEED_AVAX);
            sources[1] = AggregatorV3Interface(PRICE_FEED_USDC);

            address[] memory assets = new address[](2);
            assets[0] = WAVAX;
            assets[1] = USDC;

            StructPriceOracle oracle = new StructPriceOracle(assets, sources);
            STRUCT_PRICE_ORACLE = address(oracle);
        }

        /// Deploy GAC

        GlobalAccessControl gac = new GlobalAccessControl(deployerAddress);
        /// Deploy StructSPToken
        StructSPToken spToken = new StructSPToken(IGAC(address(gac)), IFEYFactory(address(0)));

        /// Deploy product
        DataTypes.TrancheConfig memory trancheConfigSenior =
            DataTypes.TrancheConfig({tokenAddress: IERC20Metadata(address(0)), decimals: 0, spTokenId: 0, capacity: 0});

        DataTypes.TrancheConfig memory trancheConfigJunior =
            DataTypes.TrancheConfig({tokenAddress: IERC20Metadata(address(0)), decimals: 0, spTokenId: 0, capacity: 0});

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

        FEYGMXProduct feyGMXProductImplementation = new FEYGMXProduct();

        if (STRUCT_DISTRIBUTION_MANAGER == address(0)) {
            /// Deploy DM
            IDistributionManager.RecipientData memory recipient1 =
                IDistributionManager.RecipientData(MULTISIG, allocationPoints, allocationFee);
            recipients.push(recipient1);
            DistributionManager distributionManager = new DistributionManager(
                IERC20Metadata(address(WAVAX)),
                rewardsPerSecond,
                IGAC(address(gac)),
                recipients
            );
            STRUCT_DISTRIBUTION_MANAGER = address(distributionManager);
        }

        /// Initialize product
        feyGMXProductImplementation.initialize(
            initConfigParams,
            IStructPriceOracle(STRUCT_PRICE_ORACLE),
            ISPToken(address(spToken)),
            IGAC(address(gac)),
            IDistributionManager(STRUCT_DISTRIBUTION_MANAGER),
            address(0), // Yield Source
            payable(address(WAVAX))
        );

        /// Deploy factory
        FEYGMXProductFactory feyGMXProductFactory = new FEYGMXProductFactory(
            ISPToken(address(spToken)),
            address(feyGMXProductImplementation),
            IGAC(address(gac)),
            IStructPriceOracle(STRUCT_PRICE_ORACLE),
            IERC20Metadata(address(WAVAX)),
            IDistributionManager(STRUCT_DISTRIBUTION_MANAGER)
        );

        GMXYieldSource gmxYieldSource = new GMXYieldSource(
            address(feyGMXProductFactory),
            IGAC(address(gac))
        );

        spToken.setFeyProductFactory(IFEYFactory(feyGMXProductFactory));
        feyGMXProductFactory.setYieldSource(address(gmxYieldSource));

        gac.grantRole(WHITELIST_MANAGER, deployerAddress);
        gac.grantRole(FACTORY, address(feyGMXProductFactory));
        gac.grantRole(DEFAULT_ADMIN_ROLE, address(feyGMXProductFactory));

        gac.grantRole(WHITELIST_MANAGER, MULTISIG);
        gac.grantRole(GOVERNANCE, MULTISIG);
        gac.grantRole(DEFAULT_ADMIN_ROLE, MULTISIG);

        for (uint256 index = 0; index < WHITELISTABLE_ADDRESSES.length; index++) {
            gac.grantRole(WHITELISTED, WHITELISTABLE_ADDRESSES[index]);
        }

        feyGMXProductFactory.setTokenStatus(USDC, 1);
        feyGMXProductFactory.setTokenStatus(WAVAX, 1);
        feyGMXProductFactory.setTokenStatus(BTCB, 1);

        feyGMXProductFactory.setPoolStatus(USDC, WAVAX, 1);
        feyGMXProductFactory.setPoolStatus(USDC, BTCB, 1);
        feyGMXProductFactory.setPoolStatus(WAVAX, BTCB, 1);
        feyGMXProductFactory.setPoolStatus(USDC, USDC, 1);
        feyGMXProductFactory.setPoolStatus(WAVAX, WAVAX, 1);
        feyGMXProductFactory.setPoolStatus(BTCB, BTCB, 1);

        /// @dev Important: Donot remove these renounceRole calls!
        gac.renounceRole(WHITELIST_MANAGER, deployerAddress);
        gac.renounceRole(GOVERNANCE, deployerAddress);
        gac.renounceRole(DEFAULT_ADMIN_ROLE, deployerAddress);

        vm.stopBroadcast();
    }
}
