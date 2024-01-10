// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "forge-std/src/Script.sol";
import {AddressesDevelop} from "../../deployment-helpers/develop/Addresses.sol";

import "@core/yield-sources/GMXYieldSource.sol";
import "@interfaces/IGAC.sol";
import "@interfaces/IFEYFactory.sol";

contract DeployGMXYieldSource is Script, AddressesDevelop {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GMXYieldSource gmxYieldSource = new GMXYieldSource(
            GMX_PRODUCT_FACTORY,
            IGAC(GAC)
        );

        // Manually set the yield source on the GMX product factory
        // IFEYFactory(GMX_PRODUCT_FACTORY).setYieldSource(address(gmxYieldSource));

        vm.stopBroadcast();
    }
}
