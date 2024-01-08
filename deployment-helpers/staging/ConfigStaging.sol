// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase
pragma solidity 0.8.11;

import {Config} from "../Config.sol";
import {IDistributionManager} from "@interfaces/IDistributionManager.sol";
import {Script} from "forge-std/src/Script.sol";

contract ConfigStaging is Config {
    uint256 internal allocatedTotalPoints = 1e3;
    uint256 internal allocationPoints = 1e3;
    uint256 internal allocationFee = 1e3;
    uint256 internal rewardsPerSec = 1;
    uint256 rewardsPerSecond = 0;

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_STAGING");
    address deployerAddress = vm.addr(deployerPrivateKey);
}
