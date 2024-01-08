// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

/// External imports
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
/// Internal imports
import {IAutoPoolVault} from "../../external/traderjoe/IAutoPoolVault.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {IStructPriceOracle} from "../../interfaces/IStructPriceOracle.sol";
import {IWETH9} from "../../external/IWETH9.sol";
import {AutoPoolYieldSource} from "./AutoPoolYieldSource.sol";

/**
 * @title Lowliquidity TraderJoe AutoPool Yield Source contract,
 * @dev This contract inherits GACManaged which extends Pausable also uses the GAC for access control
 * @notice Yield source for the FEYTJAutoPoolProduct that generates yield by depositing into TraderJoe AutoPools with low liquidity
 */
contract LLAutoPoolYieldSource is AutoPoolYieldSource {
    IERC20Metadata internal immutable eurocToken = IERC20Metadata(0xC891EB4cbdEFf6e073e859e987815Ed1505c2ACD);

    constructor(IAutoPoolVault _autoPoolVault, IGAC _globalAccessControl, IStructPriceOracle _structPriceOracle)
        AutoPoolYieldSource(_autoPoolVault, _globalAccessControl, _structPriceOracle)
    {}

    /**
     * @notice Used to swap tokens and add liquidity for recompounding rewards
     * @param _reward1Harvested Amount of reward1 received from harvesting rewards
     * @param _reward2Harvested Amount of reward2 received from harvesting rewards
     * @param _wavaxBalanceBefore Balance of WAVAX in the contract before harvesting rewards
     */
    function _recompoundRewards(uint256 _reward1Harvested, uint256 _reward2Harvested, uint256 _wavaxBalanceBefore)
        internal
        override
    {
        bool _hasNativeReward;

        IERC20Metadata _rewardToken1 = joeToken;
        IERC20Metadata _rewardToken2 = rewardToken2;

        /// If reward1 tokens are  neither tokenA and tokenB, swap all reward1 tokens to the native token
        if (_reward1Harvested > 0) {
            if (address(_rewardToken1) != address(tokenA) && address(_rewardToken1) != address(tokenB)) {
                /// Set _hasNativeReward to true as we are going to swap all reward1 tokens to WAVAX
                _hasNativeReward = true;
                _increaseAllowanceAndSwap(_reward1Harvested, _rewardToken1, joeToNativeSwapPath);
            }
        }

        /// If reward2 is there, it would be either WAVAX, AVAX or other token
        /// if WAVAX, then do nothing, just set `_hasNativeReward` to true, so that we can swap equally to tokenA and tokenB
        /// If AVAX. wrap it to WAVAX then do the same above.
        /// If other token, swap reward 2 accrued to wavax
        if (numRewards > 1 && _reward2Harvested > 0) {
            if (address(_rewardToken2) != address(tokenA) && address(_rewardToken2) != address(tokenB)) {
                if (isReward2Native) {
                    IWETH9(WAVAX).deposit{value: _reward2Harvested}();
                } else {
                    if (address(rewardToken2) != address(WAVAX)) {
                        _increaseAllowanceAndSwap(_reward2Harvested, _rewardToken2, reward2ToNativeSwapPath);
                    }
                }
                _hasNativeReward = true;
            }
        }
        /// If there are native tokens, check if they are srTokens or jrTokens
        /// If either of the tokens is low liquidity token like EUROC, swap the native tokens to the other tranche token
        if (_hasNativeReward) {
            uint256 nativeBalance = (IERC20Metadata(WAVAX).balanceOf(address(this)) - _wavaxBalanceBefore);
            if (nativeBalance > 0 && (address(tokenA) != address(WAVAX) && address(tokenB) != address(WAVAX))) {
                if (address(tokenA) == address(eurocToken)) {
                    _increaseAllowanceAndSwap(nativeBalance, IERC20Metadata(WAVAX), nativeToTokenBSwapPath);
                } else if (address(tokenB) == address(eurocToken)) {
                    _increaseAllowanceAndSwap(nativeBalance, IERC20Metadata(WAVAX), nativeToTokenASwapPath);
                }
            }
        }
    }
}
