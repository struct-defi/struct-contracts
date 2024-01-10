// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Internal Imports
import {IJoeRouter} from "../../external/traderjoe/IJoeRouter.sol";

import {ILBRouter} from "../../external/traderjoe/ILBRouter.sol";
import {ILBQuoter} from "../../external/traderjoe/ILBQuoter.sol";

import {Helpers} from "../libraries/helpers/Helpers.sol";

/**
 * @title TraderJoeLpAdapter
 * @notice Implements the logic for interacting with the Liquidity pools of TraderJoe
 *
 * @author Struct Finance
 *
 */

abstract contract TraderJoeLPAdapter {
    using SafeERC20 for IERC20Metadata;

    /// @dev The slippage amount
    uint256 public slippage;

    /// @dev Address of the Senior tranche token
    IERC20Metadata public trancheTokenSr;

    /// @dev Address of the Junior tranche token
    IERC20Metadata public trancheTokenJr;

    /// @dev Address of the JoeRouter contract
    IJoeRouter public immutable joeRouter = IJoeRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);

    /// @dev Address of the LiquidityBook router contract
    ILBRouter public immutable lbRouter = ILBRouter(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);

    /// @dev Address of the LiquidityBook quoter contract
    ILBQuoter public immutable lbQuoter = ILBQuoter(0x64b57F4249aA99a812212cee7DAEFEDC40B203cD);

    /**
     * @notice Used to swap from exact tokens to tokens
     * @param _amountIn Amount in
     * @param _minimumAmountOut Minimum amount expected
     * @param _path The swap path
     * @param _receiver Address of the receiver
     * @return _amtTokensReceived Tokens received after swap
     */
    function _swapExact(uint256 _amountIn, uint256 _minimumAmountOut, address[] memory _path, address _receiver)
        internal
        returns (uint256 _amtTokensReceived)
    {
        ILBQuoter.Quote memory _quote;

        _amountIn = Helpers.weiToTokenDecimals(IERC20Metadata(_path[0]).decimals(), _amountIn);

        _quote = lbQuoter.findBestPathFromAmountIn(_path, uint128(_amountIn));

        _minimumAmountOut =
            Helpers.weiToTokenDecimals(IERC20Metadata(_path[_path.length - 1]).decimals(), _minimumAmountOut);

        IERC20Metadata(_path[0]).safeIncreaseAllowance(address(lbRouter), _amountIn);

        ILBRouter.Path memory _route = ILBRouter.Path(_quote.binSteps, _quote.versions, _quote.route);

        _amtTokensReceived =
            lbRouter.swapExactTokensForTokens(_amountIn, _minimumAmountOut, _route, _receiver, block.timestamp + 1);
    }

    /**
     * @notice Used to swap tokens to exact tokens
     * @param _quote The ILBQuoter.Quote struct
     * @param _amountInMax Amount in max
     * @param _amountOut Amount out
     * @param _receiver Address of the receiver
     */
    function _swapToExact(ILBQuoter.Quote memory _quote, uint256 _amountInMax, uint256 _amountOut, address _receiver)
        internal
    {
        IERC20Metadata(_quote.route[0]).safeIncreaseAllowance(address(lbRouter), _amountInMax);

        ILBRouter.Path memory _route = ILBRouter.Path(_quote.binSteps, _quote.versions, _quote.route);

        lbRouter.swapTokensForExactTokens(_amountOut, _amountInMax, _route, _receiver, block.timestamp + 1);
    }
}
