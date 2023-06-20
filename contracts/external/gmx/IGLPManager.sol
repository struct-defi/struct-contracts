// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

interface IGLPManager {
    function getPrice(bool _maximise) external view returns (uint256);
}
