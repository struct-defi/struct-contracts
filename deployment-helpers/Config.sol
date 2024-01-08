// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase
pragma solidity 0.8.11;

import {IDistributionManager} from "@interfaces/IDistributionManager.sol";
import {Script} from "forge-std/src/Script.sol";

contract Config is Script {
    IDistributionManager.RecipientData[] internal recipients;

    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant WHITELISTED = keccak256("WHITELISTED");
    bytes32 public constant WHITELIST_MANAGER = keccak256("WHITELIST_MANAGER");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
}
