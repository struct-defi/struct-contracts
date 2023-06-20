// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IDistributionManager {
    struct RecipientData {
        address destination;
        uint256 allocationPoints;
        uint256 allocationFee;
    }

    function queueFees(uint256 _amount) external;
}
