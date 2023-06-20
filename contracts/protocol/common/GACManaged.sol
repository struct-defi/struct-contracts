// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/// Internal Imports
import "../../interfaces/IGAC.sol";

import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title Global Access Control Managed - Base Class
 * @notice Allows inheriting contracts to leverage global access control permissions conveniently, as well as granting contract-specific pausing functionality
 * @dev Inspired from https://github.com/Citadel-DAO/citadel-contracts
 */
contract GACManaged is Pausable {
    IGAC public gac;

    bytes32 internal constant PAUSER = keccak256("PAUSER");
    bytes32 internal constant WHITELISTED = keccak256("WHITELISTED");
    bytes32 internal constant KEEPER = keccak256("KEEPER");
    bytes32 internal constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 internal constant MINTER = keccak256("MINTER");
    bytes32 internal constant PRODUCT = keccak256("PRODUCT");
    bytes32 internal constant DISTRIBUTION_MANAGER = keccak256("DISTRIBUTION_MANAGER");
    bytes32 internal constant FACTORY = keccak256("FACTORY");

    /// @dev Initializer
    uint8 private isInitialized;

    /*////////////////////////////////////////////////////////////*/
    /*                           MODIFIERS                        */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @dev only holders of the given role on the GAC can access the methods with this modifier
     * @param role The role that msgSender will be checked against
     */
    modifier onlyRole(bytes32 role) {
        require(gac.hasRole(role, _msgSender()), Errors.ACE_INVALID_ACCESS);
        _;
    }

    function _gacPausable() private view {
        require(!gac.paused(), Errors.ACE_GLOBAL_PAUSED);
        require(!paused(), Errors.ACE_LOCAL_PAUSED);
    }

    /// @dev can be pausable by GAC or local flag
    modifier gacPausable() {
        _gacPausable();
        _;
    }

    /*////////////////////////////////////////////////////////////*/
    /*                           INITIALIZER                      */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializer
     * @param _globalAccessControl global access control which is pinged to allow / deny access to permissioned calls by role
     */
    function __GACManaged_init(IGAC _globalAccessControl) public {
        require(isInitialized == 0, Errors.ACE_INITIALIZER);
        isInitialized = 1;
        gac = _globalAccessControl;
    }

    /*////////////////////////////////////////////////////////////*/
    /*                      RESTRICTED ACTIONS                    */
    /*////////////////////////////////////////////////////////////*/

    /// @dev Used to pause certain actions in the contract
    function pause() public onlyRole(PAUSER) {
        _pause();
    }

    /// @dev Used to unpause if paused
    function unpause() public onlyRole(PAUSER) {
        _unpause();
    }
}
