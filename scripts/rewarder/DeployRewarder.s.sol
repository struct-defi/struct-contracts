// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "forge-std/src/Script.sol";
import "@core/common/GlobalAccessControl.sol";
import "@core/common/StructPriceOracle.sol";
import {ConfigDevelop} from "../../deployment-helpers/ConfigDevelop.sol";
import "../BaseDeployer.s.sol";

import "@core/misc/Rewarder.sol";

contract DeployRewarder is Script, ConfigDevelop, BaseDeployer {
    function run() external {
        console.log("About to deploy the Rewarder...");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEV");
        if (IS_PROD_DEPLOYMENT == 1) {
            console.log("this a PRODUCTION deployment");
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            console.log("this is a DEV deployment");
        }

        vm.startBroadcast(deployerPrivateKey);

        Rewarder rewarder = new Rewarder(IGAC(GAC), IStructPriceOracle(STRUCT_PRICE_ORACLE));
        console.log("Deployment of Rewarder successful: ", address(rewarder));
        emit Deployed("Struct", "Rewarder");

        vm.stopBroadcast();
    }
}
