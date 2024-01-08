// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console
pragma solidity 0.8.11;

import {Script} from "forge-std/src/Script.sol";

import {FEYAutoPoolProductLens} from "@core/lens/FEYAutoPoolProductLens.sol";
import {BaseDeployer} from "../BaseDeployer.s.sol";
import {ConfigDevelop} from "../../deployment-helpers/develop/ConfigDevelop.sol";
import {console} from "forge-std/src/console.sol";

contract DeployAutoPoolProductLens is Script, BaseDeployer, ConfigDevelop {
    function run() external {
        console.log("About to deploy");

        vm.startBroadcast(deployerPrivateKey);

        FEYAutoPoolProductLens lens = new FEYAutoPoolProductLens();

        console.log("Deployment of FEYAutoPoolProductLens success: ", address(lens));
        emit Deployed("AutoPool", "FEYProductLens");

        vm.stopBroadcast();
    }
}
