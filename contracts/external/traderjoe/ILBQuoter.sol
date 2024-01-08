// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {ILBRouter} from "./ILBRouter.sol";

/**
 * @title Liquidity Book Router Interface
 * @author Trader Joe
 * @notice Required interface of LBRouter contract
 */
interface ILBQuoter {
    /**
     * @dev The quote struct returned by the quoter
     * - route: address array of the token to go through
     * - pairs: address array of the pairs to go through
     * - binSteps: The bin step to use for each pair
     * - versions: The version to use for each pair
     * - amounts: The amounts of every step of the swap
     * - virtualAmountsWithoutSlippage: The virtual amounts of every step of the swap without slippage
     * - fees: The fees to pay for every step of the swap
     */
    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        ILBRouter.Version[] versions;
        uint128[] amounts;
        uint128[] virtualAmountsWithoutSlippage;
        uint128[] fees;
    }

    function findBestPathFromAmountIn(address[] memory route, uint128 amountIn)
        external
        view
        returns (Quote memory quote);

    function findBestPathFromAmountOut(address[] memory route, uint128 amountOut)
        external
        view
        returns (Quote memory quote);
}
