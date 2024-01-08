// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoringOwnableData {
    address public owner;
    address public pendingOwner;
}

contract BoringOwnable is BoringOwnableData {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice `owner` defaults to msg.sender on construction.
    constructor() public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Transfers ownership to `newOwner`. Either directly or claimable by the new pending owner.
    /// Can only be invoked by the current `owner`.
    /// @param newOwner Address of the new owner.
    /// @param direct True if `newOwner` should be set immediately. False if `newOwner` needs to use `claimOwnership`.
    /// @param renounce Allows the `newOwner` to be `address(0)` if `direct` and `renounce` is True. Has no effect otherwise.
    function transferOwnership(address newOwner, bool direct, bool renounce) public onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0) || renounce, "Ownable: zero address");

            // Effects
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
            pendingOwner = address(0);
        } else {
            // Effects
            pendingOwner = newOwner;
        }
    }

    /// @notice Needs to be called by `pendingOwner` to claim ownership.
    function claimOwnership() public {
        address _pendingOwner = pendingOwner;

        // Checks
        require(msg.sender == _pendingOwner, "Ownable: caller != pending owner");

        // Effects
        emit OwnershipTransferred(owner, _pendingOwner);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Only allows the `owner` to execute the function.
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
}

interface IRewardooor {
    function onJoeReward(address user, uint256 newLpAmount, uint256 aptSupply) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}

interface IMasterChefJoe {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this poolInfo. SUSHI to distribute per block.
        uint256 lastRewardTimestamp; // Last block timestamp that SUSHI distribution occurs.
        uint256 accJoePerShare; // Accumulated SUSHI per share, times 1e12. See below.
    }

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;
}

/**
 * This is a sample contract to be used in the MasterChefJoe contract for partners to reward
 * stakers with their native token alongside JOE.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 *
 * Issue with the previous version is that this fraction, `tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)`,
 * can return 0 or be very inacurate with some tokens:
 *      uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
 *      uint256 tokenReward = timeElapsed.mul(tokenPerSec);
 *      accTokenPerShare = accTokenPerShare.add(
 *          tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)
 *      );
 *  The goal is to set ACC_TOKEN_PRECISION high enough to prevent this without causing overflow too.
 */
contract MockRewarder is IRewardooor, BoringOwnable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Info of each MCJ user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each MCJ poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    IERC20 public immutable override rewardToken;
    bool public immutable isNative;
    uint256 public tokenPerSec = 1e15;
    mapping(address => uint256) public lastClaimed;

    // Given the fraction, tokenReward * ACC_TOKEN_PRECISION / lpSupply, we consider
    // several edge cases.
    //
    // Edge case n1: maximize the numerator, minimize the denominator.
    // `lpSupply` = 1 WEI
    // `tokenPerSec` = 1e(30)
    // `timeElapsed` = 31 years, i.e. 1e9 seconds
    // result = 1e9 * 1e30 * 1e36 / 1
    //        = 1e75
    // (No overflow as max uint256 is 1.15e77).
    // PS: This will overflow when `timeElapsed` becomes greater than 1e11, i.e. in more than 3_000 years
    // so it should be fine.
    //
    // Edge case n2: minimize the numerator, maximize the denominator.
    // `lpSupply` = max(uint112) = 1e34
    // `tokenPerSec` = 1 WEI
    // `timeElapsed` = 1 second
    // result = 1 * 1 * 1e36 / 1e34
    //        = 1e2
    // (Not rounded to zero, therefore ACC_TOKEN_PRECISION = 1e36 is safe)
    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;
    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    constructor(address _rewardToken, bool _isNative) public {
        rewardToken = IERC20(_rewardToken);
        isNative = _isNative;
        poolInfo = PoolInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice payable function needed to receive AVAX
    receive() external payable {
        require(isNative, "Non native rewarder");
    }

    function onJoeReward(address _user, uint256 newLpAmount, uint256 aptSupply) external override nonReentrant {
        if (_user == address(0)) return;
        if (lastClaimed[_user] == 0) lastClaimed[_user] = block.timestamp - 10000;
        uint256 timeElapsed = block.timestamp - lastClaimed[_user];
        lastClaimed[_user] = block.timestamp;

        uint256 pendingRewards = timeElapsed * tokenPerSec;

        if (isNative == true) {
            (bool success,) = _user.call{value: pendingRewards}("");
            require(success, "Transfer failed");
        } else {
            rewardToken.safeTransfer(_user, pendingRewards);
        }

        emit OnReward(_user, pendingRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        uint256 timeElapsed = block.timestamp - lastClaimed[_user];

        pending = timeElapsed * tokenPerSec;
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        if (isNative) {
            return address(this).balance;
        } else {
            return rewardToken.balanceOf(address(this));
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (isNative) {
            (bool success,) = msg.sender.call{value: address(this).balance}("");
            require(success, "Transfer failed");
        } else {
            rewardToken.safeTransfer(address(msg.sender), rewardToken.balanceOf(address(this)));
        }
    }
}
