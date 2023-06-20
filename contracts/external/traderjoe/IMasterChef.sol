// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

interface IMasterChef {
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOE to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that JOE distribution occurs.
        uint256 accJoePerShare; // Accumulated JOE per share, times 1e12. See below.
    }

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256, address, string memory, uint256);

    function poolLength() external view returns (uint256);

    function rewarderBonusTokenInfo(uint256 _pid) external view returns (address, string memory);
}
