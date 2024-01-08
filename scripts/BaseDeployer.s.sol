// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "forge-std/src/Script.sol";

contract BaseDeployer is Script {
    event Deployed(string platform, string strategy);
}
