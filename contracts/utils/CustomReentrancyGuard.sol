// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/// @notice Gas & bytecode optimized reentrancy protection for smart contracts.
/// @author Struct Finance
/// @author Modified from Solmate to make it compatible with OZ Clones (https://github.com/Rari-Capital/solmate/blob/main/src/utils/ReentrancyGuard.sol)
abstract contract CustomReentrancyGuard {
    uint256 private reentrancyStatus = 1;

    modifier nonReentrant() {
        _nonReentrant();
        _;

        reentrancyStatus = 1;
    }

    function _nonReentrant() private {
        require(reentrancyStatus < 2, "REENTRANCY");

        reentrancyStatus = 2;
    }
}
