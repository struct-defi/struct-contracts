/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/**
 * @title The GlobalAccessControl interface
 * @author Struct Finance
 *
 */

interface IGAC {
    /// @notice Used to unpause the contracts globally if it's paused
    function unpause() external;

    /// @notice Used to pause the contracts globally if it's paused
    function pause() external;

    /// @notice Used to grant a specific role to an address
    /// @param role The role to be granted
    /// @param account The address to which the role should be granted
    function grantRole(bytes32 role, address account) external;

    /// @notice Used to validate whether the given address has a specific role
    /// @param role The role to check
    /// @param account The address which should be validated
    /// @return A boolean flag that indicates whether the given address has the required role
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @notice Used to check if the contracts are paused globally
    /// @return A boolean flag that indicates whether the contracts are paused or not.
    function paused() external view returns (bool);

    /// @notice Used to fetch the roles array `KEEPER_WHITELISTED`
    /// @return An array with the `KEEPER` and `WHITELISTED` roles
    function keeperWhitelistedRoles() external view returns (bytes32[] memory);
}
