// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

interface IGMXRewardRouterV2 {
    function stakedGmxTracker() external view returns (address);

    function bonusGmxTracker() external view returns (address);

    function feeGmxTracker() external view returns (address);

    function stakedGlpTracker() external view returns (address);

    function feeGlpTracker() external view returns (address);

    function glpManager() external view returns (address);

    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp)
        external
        returns (uint256);

    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _reciever)
        external
        returns (uint256);

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}
