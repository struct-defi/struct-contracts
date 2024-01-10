// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onJoeReward(address user, uint256 newLpAmount, uint256 aptSupply) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}

interface IAPTFarm {
    error APTFarm__InvalidAPToken();
    error APTFarm__ZeroAmount();
    error APTFarm__EmptyArray();
    error APTFarm__ZeroAddress();
    error APTFarm__InvalidJoePerSec();
    error APTFarm__InvalidFarmIndex();
    error APTFarm__TokenAlreadyHasFarm(address apToken);
    error APTFarm__InsufficientDeposit(uint256 deposit, uint256 amountWithdrawn);

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed apToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateFarm(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount, uint256 unpaidAmount);
    event BatchHarvest(address indexed user, uint256[] pids);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Skim(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Info of each APTFarm user.
     * `amount` LP token amount the user has provided.
     * `rewardDebt` The amount of JOE entitled to the user.
     * `unpaidRewards` The amount of JOE that could not be transferred to the user.
     */
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /**
     * @notice Info of each APTFarm farm.
     * `apToken` Address of the LP token.
     * `accJoePerShare` Accumulated JOE per share.
     * `lastRewardTimestamp` Last timestamp that JOE distribution occurs.
     * `joePerSec` JOE tokens distributed per second.
     * `rewarder` Address of the rewarder contract that handles the distribution of bonus tokens.
     */
    struct FarmInfo {
        IERC20 apToken;
        uint256 accJoePerShare;
        uint256 lastRewardTimestamp;
        uint256 joePerSec;
        IRewarder rewarder;
    }

    function joe() external view returns (IERC20 joe);

    function hasFarm(address apToken) external view returns (bool hasFarm);

    function vaultFarmId(address apToken) external view returns (uint256 vaultFarmId);

    function apTokenBalances(IERC20 apToken) external view returns (uint256 apTokenBalance);

    function farmLength() external view returns (uint256 farmLength);

    function farmInfo(uint256 pid) external view returns (FarmInfo memory farmInfo);

    function userInfo(uint256 pid, address user) external view returns (UserInfo memory userInfo);

    function add(uint256 joePerSec, IERC20 apToken, IRewarder rewarder) external;

    function set(uint256 pid, uint256 joePerSec, IRewarder rewarder, bool overwrite) external;

    function pendingTokens(uint256 pid, address user)
        external
        view
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        );

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function harvestRewards(uint256[] calldata pids) external;

    function emergencyWithdraw(uint256 pid) external;

    function skim(IERC20 token, address to) external;
}
