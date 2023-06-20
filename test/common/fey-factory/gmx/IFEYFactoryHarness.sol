// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@interfaces/IFEYFactory.sol";
import "@interfaces/IStructPriceOracle.sol";

interface IFEYFactoryHarness is IFEYFactory {
    function setPerformanceFee(uint256 _performanceFee) external;

    function setManagementFee(uint256 _managementFee) external;

    function setMinimumTrancheDuration(uint256 _trancheDurationMin) external;

    function setMaximumTrancheDuration(uint256 _trancheDurationMax) external;

    function setLeverageThresholdMinCap(uint256 _levThresholdMin) external;

    function setLeverageThresholdMaxCap(uint256 _levThresholdMax) external;

    function setTrancheCapacity(uint256 _trancheCapUSD) external;

    function setFEYProductImplementation(address _feyProductImpl) external;

    function setStructPriceOracle(IStructPriceOracle _structPriceOracle) external;

    function setMinimumDepositValueUSD(uint256 _newValue) external;

    function setTokenStatus(address _token, uint256 _status) external;

    function setMaxFixedRate(uint256 _fixedRateMax) external;

    function setYieldSource(address _yieldSource) external;

    function setPoolStatus(address _token0, address _token1, uint256 _status) external;

    function leverageThresholdMinCap() external view returns (uint256);

    function leverageThresholdMaxCap() external view returns (uint256);

    function trancheDurationMin() external view returns (uint256);

    function trancheDurationMax() external view returns (uint256);

    function trancheCapacityUSD() external view returns (uint256 trancheCapacityUSD);

    function feyProductImplementation() external view returns (address);

    function structPriceOracle() external view returns (IStructPriceOracle);

    function minimumInitialDepositUSD() external view returns (uint256);

    function yieldSource() external view returns (address yieldSource);

    function managementFee() external view returns (uint256);

    function performanceFee() external view returns (uint256);

    function productTokenId(uint256 spTokenId) external view returns (address productAddress);

    function maxFixedRate() external view returns (uint256);

    function getFirstProduct() external view returns (address);
}
