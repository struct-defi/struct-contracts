// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import "@openzeppelin/contracts/access/AccessControl.sol";

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/// Internal Imports
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title Global Access Control
 * @notice Allows inheriting contracts to leverage global access control permissions conveniently,
 *         as well as granting contract-specific pausing functionality
 * @dev Inspired from https://github.com/Citadel-DAO/citadel-contracts
 */
contract GlobalAccessControl is Pausable, AccessControl {
    /*////////////////////////////////////////////////////////////*/
    /*                           ROLES                            */
    /*////////////////////////////////////////////////////////////*/

    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant POLICY_OPS = keccak256("POLICY_OPS");
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant MINTER = keccak256("MINTER");
    bytes32 public constant TREASURY_OPS = keccak256("TREASURY_OPS");
    bytes32 public constant WHITELISTED = keccak256("WHITELISTED");
    bytes32 public constant WHITELIST_MANAGER = keccak256("WHITELIST_MANAGER");
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant DISTRIBUTION_MANAGER = keccak256("DISTRIBUTION_MANAGER");
    bytes32 public constant CREATOR = keccak256("CREATOR");
    bytes32[] private KEEPER_WHITELISTED = [KEEPER, WHITELISTED];

    /*////////////////////////////////////////////////////////////*/
    /*                           CONSTRUCTOR                      */
    /*////////////////////////////////////////////////////////////*/
    constructor(address _defaultAdmin) {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(GOVERNANCE, _defaultAdmin);
        _setRoleAdmin(PRODUCT, FACTORY);

        // All roles are managed by GOVERNANCE_ROLE
        _setRoleAdmin(PAUSER, GOVERNANCE);
        _setRoleAdmin(POLICY_OPS, GOVERNANCE);
        _setRoleAdmin(TREASURY_OPS, GOVERNANCE);
        _setRoleAdmin(PAUSER, GOVERNANCE);
        _setRoleAdmin(WHITELIST_MANAGER, GOVERNANCE);
        _setRoleAdmin(KEEPER, GOVERNANCE);
        _setRoleAdmin(MINTER, GOVERNANCE);
        _setRoleAdmin(FACTORY, GOVERNANCE);

        // Add default admin role here to avoid governance mistakes
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, GOVERNANCE);

        // WHITELISTED is managed by WHITELIST_MANAGER
        _setRoleAdmin(WHITELISTED, WHITELIST_MANAGER);
    }

    /*////////////////////////////////////////////////////////////*/
    /*            Permissioned Actions (various roles)            */
    /*////////////////////////////////////////////////////////////*/

    /// @notice Pause the protocol globally
    function pause() public {
        require(hasRole(PAUSER, _msgSender()), Errors.ACE_INVALID_ACCESS);
        _pause();
    }

    /// @notice Unpause the protocol if paused
    function unpause() public {
        require(hasRole(PAUSER, _msgSender()), Errors.ACE_INVALID_ACCESS);
        _unpause();
    }

    /**
     * @dev Used to set admin role for a role
     * @param role The role that will have adminRole as its admin
     * @param adminRole The hash of the role string
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    /**
     * @dev Setup a new role via contract governance, without upgrade
     * @dev Note that no constant will be available on the contract here to search role, but we can delegate viewing to another contract
     * @param role The new role being initialized
     * @param roleString The string of the role being initialized
     * @param adminRole The admin of the new role
     */
    function initializeNewRole(bytes32 role, string memory roleString, bytes32 adminRole) public {
        require(
            hasRole(GOVERNANCE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), Errors.ACE_INVALID_ACCESS
        );
        require(keccak256(bytes(roleString)) == role, Errors.ACE_HASH_MISMATCH);
        _setRoleAdmin(role, adminRole);
    }

    function keeperWhitelistedRoles() external view returns (bytes32[] memory) {
        return KEEPER_WHITELISTED;
    }
}
