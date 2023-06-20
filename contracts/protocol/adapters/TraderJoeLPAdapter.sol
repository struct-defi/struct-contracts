// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Internal Imports
import {IJoeRouter} from "../../external/traderjoe/IJoeRouter.sol";
import {IJoeFactory} from "../../external/traderjoe/IJoeFactory.sol";
import {IMasterChef} from "../../external/traderjoe/IMasterChef.sol";

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Helpers} from "../libraries/helpers/Helpers.sol";
import {Constants} from "../libraries/helpers/Constants.sol";

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

    /// @dev Address of the MasterChef contract
    IMasterChef public immutable masterChef = IMasterChef(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);

    /*////////////////////////////////////////////////////////////*/
    /*                      INTERNAL METHODS                      */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to swap tokens
     * @param amtIn Amount in
     * @param amtOutMin Minimum amount expected
     * @param _path The swap path
     * @return _amtTokensReceived Tokens received after swap
     */
    function _swapExact(uint256 amtIn, uint256 amtOutMin, address[] memory _path)
        internal
        returns (uint256 _amtTokensReceived)
    {
        uint256 _amtIn = (amtIn * 10 ** IERC20Metadata(_path[0]).decimals()) / Constants.WAD;
        uint256 _amtOutMin = (amtOutMin * 10 ** IERC20Metadata(_path[_path.length - 1]).decimals()) / Constants.WAD;
        IERC20Metadata(_path[0]).safeIncreaseAllowance(address(joeRouter), amtIn);
        _amtTokensReceived = joeRouter.swapExactTokensForTokens(
            _amtIn, _amtOutMin, _path, address(this), block.timestamp
        )[_path.length - 1];
    }

    /*////////////////////////////////////////////////////////////*/
    /*                           VIEWS                            */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the LP Token address of the given pair
     * @return _lpTokenAddress Address of the LP token
     */
    function _getLpToken() private view returns (address _lpTokenAddress) {
        _lpTokenAddress = IJoeFactory(joeRouter.factory()).getPair(address(trancheTokenSr), address(trancheTokenJr));
    }

    function getLpToken() public view returns (address) {
        return _getLpToken();
    }
}
