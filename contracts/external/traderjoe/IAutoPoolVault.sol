// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Base Vault Interface
 * @notice Interface used to interact with Liquidity Book Vaults
 */
interface IAutoPoolVault is IERC20Metadata {
    struct QueuedWithdrawal {
        mapping(address => uint256) userWithdrawals;
        uint256 totalQueuedShares;
        uint128 totalAmountX;
        uint128 totalAmountY;
    }

    function getPair() external view returns (address);

    function getTokenX() external view returns (address);

    function getTokenY() external view returns (address);

    function getOracleX() external view returns (address);

    function getOracleY() external view returns (address);

    function getBalances() external view returns (uint256 amountX, uint256 amountY);

    function previewShares(uint256 amountX, uint256 amountY)
        external
        view
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function previewAmounts(uint256 shares) external view returns (uint256 amountX, uint256 amountY);

    function getCurrentRound() external view returns (uint256 round);

    function getQueuedWithdrawal(uint256 round, address user) external view returns (uint256 shares);

    function getTotalQueuedWithdrawal(uint256 round) external view returns (uint256 totalQueuedShares);

    function getCurrentTotalQueuedWithdrawal() external view returns (uint256 totalQueuedShares);

    function getStrategy() external view returns (address);

    function getRedeemableAmounts(uint256 round, address user)
        external
        view
        returns (uint256 amountX, uint256 amountY);

    function deposit(uint256 amountX, uint256 amountY)
        external
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function depositNative(uint256 amountX, uint256 amountY)
        external
        payable
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);

    function queueWithdrawal(uint256 shares, address recipient) external returns (uint256 round);

    function cancelQueuedWithdrawal(uint256 shares) external returns (uint256 round);

    function redeemQueuedWithdrawal(uint256 round, address recipient)
        external
        returns (uint256 amountX, uint256 amountY);

    function redeemQueuedWithdrawalNative(uint256 round, address recipient)
        external
        returns (uint256 amountX, uint256 amountY);

    function emergencyWithdraw() external;

    function setEmergencyMode() external;

    function isDepositsPaused() external view returns (bool);
}
