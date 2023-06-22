// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Struct Finance
 * @title Contract that receives the distribution of token allocations and protocol revenue
 *
 * @dev The contract acts as the recipient of Struct token allocations and protocol revenue from the distribution manager contract.
 * The rewards distribution manager is specified in the constructor and can be updated only by the contract owner.
 * The contract emits the RewardReceived event whenever a reward is received and the
 * DistributionManagerUpdated event whenever the distribution manager is updated.
 * The notifyRewardAmount function can only be called by the rewards distribution manager
 * to notify the contract of the received reward.
 */
contract RewardsRecipient is Ownable {
    /**
     * @dev Address of the rewards distribution manager contract
     */
    address public distributionManager;

    /**
     * @dev Emitted when a reward is received
     * @param amount amount of the reward
     * @param token address of the token receiving the reward
     */
    event RewardReceived(uint256 amount, address token);

    /**
     * @dev Emitted when the rewards distribution manager is updated
     * @param _distributionManager address of the new rewards distribution manager
     */
    event DistributionManagerUpdated(address _distributionManager);

    /**
     * @dev Modifier to check if the caller is the rewards distribution manager
     */
    modifier onlyDistributionManager() {
        require(msg.sender == distributionManager, "Caller is not Distribution Manager contract");
        _;
    }

    /**
     * @dev Function to update the rewards distribution manager
     * @param _distributionManager address of the new rewards distribution manager
     */
    function setDistributionManager(address _distributionManager) external onlyOwner {
        distributionManager = _distributionManager;
        emit DistributionManagerUpdated(_distributionManager);
    }

    /**
     * @dev Function to notify the contract of the received reward
     * @param amount amount of the reward
     * @param token address of the token receiving the reward
     */
    function notifyRewardAmount(uint256 amount, address token) external onlyDistributionManager {
        emit RewardReceived(amount, token);
    }
}
