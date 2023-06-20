// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./IDistributionManagerHarness.sol";

/**
 * @title Struct Distribution Manager User contract
 * @notice User contract to interact with Distribution Manager Contract.
 *
 */
contract DistributionManagerUser is ERC1155Holder {
    IDistributionManagerHarness public distributionManager;

    constructor(address _distributionManager) {
        distributionManager = IDistributionManagerHarness(_distributionManager);
    }

    function initialize(IERC20Metadata _structToken) external {
        distributionManager.initialize(_structToken);
    }

    function addDistributionRecipient(address _destination, uint256 _allocationPoints, uint256 _allocationFee)
        external
    {
        distributionManager.addDistributionRecipient(_destination, _allocationPoints, _allocationFee);
    }

    function removeDistributionRecipient(uint256 index) external {
        distributionManager.removeDistributionRecipient(index);
    }

    function editDistributionRecipient(
        uint256 _index,
        address _destination,
        uint256 _allocationPoints,
        uint256 _allocationFee
    ) external {
        distributionManager.editDistributionRecipient(_index, _destination, _allocationPoints, _allocationFee);
    }

    function setRewardsPerSecond(uint256 _newRewardsPerSecond) external {
        distributionManager.setRewardsPerSecond(_newRewardsPerSecond);
    }
}
