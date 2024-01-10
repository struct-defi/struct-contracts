// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@core/misc/Rewarder.sol";

contract RewarderHarness is Rewarder {
    constructor(IGAC _globalAccessControl, IStructPriceOracle _priceOracle)
        Rewarder(_globalAccessControl, _priceOracle)
    {}

    function setAllocationDetails(
        address _product,
        address _rewardToken,
        uint256 _rewardSr,
        uint256 _rewardJr,
        bool _immediateDistribution
    ) external {
        allocationDetails[_product][_rewardToken].rewardSr = _rewardSr;
        allocationDetails[_product][_rewardToken].rewardJr = _rewardJr;
        allocationDetails[_product][_rewardToken].immediateDistribution = _immediateDistribution;
    }

    function setClaimed(
        address _investor,
        address _product,
        address _rewardToken,
        uint256 _claimedSr,
        uint256 _claimedJr
    ) external {
        investorDetails[_investor][_product][_rewardToken].claimedSr = _claimedSr;
        investorDetails[_investor][_product][_rewardToken].claimedJr = _claimedJr;
    }
}
