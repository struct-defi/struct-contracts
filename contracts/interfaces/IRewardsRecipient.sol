/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/**
 * @title The Rewards Distribution Recipient interface
 * @notice For receiving rewards from the Distribution Manager
 * @author Struct Finance
 *
 */
interface IRewardsRecipient {
    function notifyRewardAmount(uint256 amount, address token) external;
}
