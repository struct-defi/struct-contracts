// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IDistributionManager.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IDistributionManagerHarness is IDistributionManager {
    function addDistributionRecipient(address _destination, uint256 _allocationPoints, uint256 _allocationFee)
        external;

    function removeDistributionRecipient(uint256 index) external;

    function editDistributionRecipient(
        uint256 _index,
        address _destination,
        uint256 _allocationPoints,
        uint256 _allocationFee
    ) external;

    function setRewardsPerSecond(uint256 _newRewardsPerSecond) external;
    function initialize(IERC20Metadata _structToken) external;
}
