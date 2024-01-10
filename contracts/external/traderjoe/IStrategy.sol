// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/**
 * @title Strategy Interface
 * @author Trader Joe
 * @notice Interface used to interact with Liquidity Book Vaults' Strategies
 */
interface IStrategy {
    function rebalance(
        uint24 newLower,
        uint24 newUpper,
        uint24 desiredActiveId,
        uint24 slippageActiveId,
        uint256 amountX,
        uint256 amountY,
        bytes calldata distributions
    ) external;
}
