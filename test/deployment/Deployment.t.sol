// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase
// solhint-disable no-console
pragma solidity ^0.8.11;

import "../../scripts/autopool/DeployAutoPoolProductLens.s.sol";
import "../../scripts/autopool/develop/DeployAutoPoolProductAndFactoryDevelop.s.sol";
import "../../scripts/autopool/staging/DeployAutoPoolProductAndFactoryStaging.s.sol";
import "../../scripts/autopool/production/DeployAutoPoolProductAndFactoryProduction.s.sol";
import "forge-std/src/Test.sol";

contract DeploymentTest is Test {
    DeployAutoPoolProductLens internal tjapLensDeployer;
    DeployAutoPoolProductAndFactoryDevelop internal tjapProductAndFactoryDevelopDeployer;
    DeployAutoPoolProductAndFactoryStaging internal tjapProductAndFactoryStagingDeployer;
    DeployAutoPoolProductAndFactoryProduction internal tjapProductAndFactoryProductionDeployer;

    event Deployed(string platform, string strategy);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC"));
        initDeployers();
    }

    function initDeployers() public {
        tjapLensDeployer = new DeployAutoPoolProductLens();
        tjapProductAndFactoryDevelopDeployer = new DeployAutoPoolProductAndFactoryDevelop();
        tjapProductAndFactoryStagingDeployer = new DeployAutoPoolProductAndFactoryStaging();
        tjapProductAndFactoryProductionDeployer = new DeployAutoPoolProductAndFactoryProduction();
    }

    function testDeploy_TJAP_Lens() public {
        console.log("should deploy the TJAP lens contract");
        vm.expectEmit(false, false, false, true);
        emit Deployed("AutoPool", "FEYProductLens");
        tjapLensDeployer.run();
    }

    function testDeploy_TJAP_ProductAndFactoryDevelop() public {
        console.log("should deploy the TJAP contracts");
        vm.expectEmit(false, false, false, true);
        emit Deployed("AutoPool", "TJAP contracts");
        tjapProductAndFactoryDevelopDeployer.run();
    }

    function testDeploy_TJAP_ProductAndFactoryStaging() public {
        console.log("should deploy the TJAP contracts");
        vm.expectEmit(false, false, false, true);
        emit Deployed("AutoPool", "TJAP contracts");
        tjapProductAndFactoryStagingDeployer.run();
    }

    function testDeploy_TJAP_ProductAndFactoryProduction() public {
        console.log("should deploy the TJAP contracts");
        vm.expectEmit(false, false, false, true);
        emit Deployed("AutoPool", "TJAP contracts");
        tjapProductAndFactoryProductionDeployer.run();
    }

    function setContractsLabels() internal {
        vm.label(address(tjapLensDeployer), "TJAP Lens Deployer");
        vm.label(address(tjapProductAndFactoryDevelopDeployer), "TJAP Develop Deployer");
        vm.label(address(tjapProductAndFactoryStagingDeployer), "TJAP Staging Deployer");
        vm.label(address(tjapProductAndFactoryProductionDeployer), "TJAP Production Deployer");
    }
}
