// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

interface IJoeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
