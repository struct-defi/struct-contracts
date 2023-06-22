// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDistributionManager} from "../../interfaces/IDistributionManager.sol";
import {IJoeRouter} from "../../external/traderjoe/IJoeRouter.sol";
import {CustomReentrancyGuard} from "../../utils/CustomReentrancyGuard.sol";

import {Errors} from "../libraries/helpers/Errors.sol";
import {GACManaged} from "../common/GACManaged.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {IRewardsRecipient} from "../../interfaces/IRewardsRecipient.sol";

/// @author Struct Finance
/// @title Contract that manages the distribution of token allocations and protocol revenue

contract DistributionManager is IDistributionManager, GACManaged, CustomReentrancyGuard {
    /// @dev Uses SafeERC20 to interact with ERC20 tokens safely.
    using SafeERC20 for IERC20Metadata;

    /// <=============== STATE VARIABLES ===============>

    /// @dev Total allocation points for token distribution.
    uint256 public totalAllocationPoints;

    /// @dev Total allocation points for fee distribution.
    uint256 public totalAllocationFee;

    /// @dev Rewards being distributed per second based on token distribution.
    uint256 public rewardsPerSecond;

    /// @dev The last distribution timestamp.
    uint256 public lastUpdateTime;

    /// @dev Native tokens accrued and queuing for distribution.
    uint256 public queuedNative;

    /// @dev Indicates if the contract has been initialized.
    bool public isInitialized;

    /// @dev Array of addresses and their token and fee allocation.
    RecipientData[] public recipients;

    /// @dev The STRUCT token contract.
    IERC20Metadata public structToken;

    /// @dev The WAVAX token contract.
    IERC20Metadata public nativeToken;

    /// @dev Joe router contract.
    IJoeRouter public router;

    /// <=============== EVENTS ===============>

    /// @dev Event emitted when rewards are distributed.
    event DistributionRewards(uint256 _distributionAmount);

    /// @dev Event emitted when fees are queued.
    event QueueFees(uint256 _queuedNative);

    /// @dev Event emitted when a recipient is added.
    event AddRecipient(uint256 _index, address indexed _destination, uint256 _allocationPoints, uint256 _allocationFee);

    /// @dev Event emitted when a recipient is edited.
    event EditRecipient(
        uint256 _index, address indexed _destination, uint256 _allocationPoints, uint256 _allocationFee
    );

    /// @dev Event emitted when rewards are added.
    event RewardAdded(uint256 _allocatedTotal, uint256 periodFinish, uint256 _excess);

    /// @dev Event emitted when rewards per second is updated.
    event RewardsPerSecondUpdate(uint256 _rewardsPerSecond);

    /**
     * @notice Contract constructor that initializes the contract and its variables.
     * @param _nativeToken The token contract that rewards are distributed in.
     * @param _rewardsPerSecond The rate at which rewards are distributed per second.
     * @param _globalAccessControl The global access control contract.
     * @param _recipientData An array of initial recipients that rewards are distributed to
     */
    constructor(
        IERC20Metadata _nativeToken,
        uint256 _rewardsPerSecond,
        IGAC _globalAccessControl,
        RecipientData[] memory _recipientData
    ) {
        nativeToken = _nativeToken;
        __GACManaged_init(_globalAccessControl);
        rewardsPerSecond = _rewardsPerSecond;
        lastUpdateTime = block.timestamp;

        /// Initialize for initial recipients
        uint256 _totalAllocationPoints;
        uint256 _totalAllocationFee;

        for (uint256 i = 0; i < _recipientData.length; i++) {
            _validateRecipientConfig(
                _recipientData[i].destination, _recipientData[i].allocationPoints, _recipientData[i].allocationFee
            );
            recipients.push(_recipientData[i]);
            _totalAllocationPoints += _recipientData[i].allocationPoints;
            _totalAllocationFee += _recipientData[i].allocationFee;
        }

        totalAllocationPoints = _totalAllocationPoints;
        totalAllocationFee = _totalAllocationFee;
    }

    /**
     * Initializer for STRUCT token.
     * @dev Initialize the contract for the STRUCT token.
     * @notice Allows the contract to get the struct token address after the contract has been deployed.
     * @notice Can only be called once.
     * @param _structToken The address of the STRUCT token contract.
     */
    function initialize(IERC20Metadata _structToken) external onlyRole(GOVERNANCE) {
        require(!isInitialized, Errors.ACE_INITIALIZER);
        require(address(_structToken) != address(0), Errors.AE_ZERO_ADDRESS);
        isInitialized = true;
        structToken = _structToken;
    }

    /// <=============== MUTATIVE METHODS ===============>

    /**
     * @notice Distributes rewards from protocol fees and token distribution to recipients.
     * @dev Loops through the array of recipient data to calculate the recipient's token and fee allocation.
     * @dev Method then calls notifyRewardAmount in recipient contracts to transfer the allocated Struct and native tokens.
     */
    function distributeRewards() public nonReentrant {
        if (totalAllocationPoints == 0 || totalAllocationFee == 0) return;

        uint256 timeElapsed = block.timestamp - lastUpdateTime;

        require(recipients.length != 0, Errors.VE_NO_RECIPIENTS);

        lastUpdateTime = block.timestamp;

        /// Loop through recipient array and distribute rewards
        for (uint256 i = 0; i < recipients.length; i++) {
            /// Account for token distribution
            uint256 allocatedTokens =
                (timeElapsed * rewardsPerSecond * recipients[i].allocationPoints) / totalAllocationPoints;

            /// Account for fee distribution
            uint256 allocatedFees = (queuedNative * recipients[i].allocationFee) / totalAllocationFee;

            require(structToken.balanceOf(address(this)) >= allocatedTokens, Errors.VE_INVALID_DISTRIBUTION_TOKEN);

            structToken.safeTransfer(recipients[i].destination, allocatedTokens);

            require(nativeToken.balanceOf(address(this)) >= allocatedFees, Errors.VE_INVALID_DISTRIBUTION_FEE);
            nativeToken.safeTransfer(recipients[i].destination, allocatedFees);

            /// Inform recipient contract how much STRUCT it received
            IRewardsRecipient(recipients[i].destination).notifyRewardAmount(allocatedTokens, address(structToken));

            /// Inform recipient contract how much native token it received
            IRewardsRecipient(recipients[i].destination).notifyRewardAmount(allocatedFees, address(nativeToken));
        }

        uint256 distributionAmount = timeElapsed * rewardsPerSecond + queuedNative;

        /// all native fees distributed - reset to zero
        queuedNative = 0;

        emit DistributionRewards(distributionAmount);
    }

    /// <=============== RESTRICTED METHODS ===============>
    /**
     * @notice Queue the fees until reward is distributed
     * @param _amount The amount of fees to queue, in native tokens
     */
    function queueFees(uint256 _amount) external onlyRole(PRODUCT) {
        /// Fees queued for next distribution, in native tokens;
        if (_amount > 0) {
            queuedNative = queuedNative + _amount;
            emit QueueFees(queuedNative);
        }
    }

    /**
     * @notice Allows owner to add a new recipient into the RecipientData array
     * @notice Only callable by the Governance role.
     * @param _destination The address of the new recipient
     * @param _allocationPoints The number of allocation points the new recipient will receive
     * @param _allocationFee The amount of fees the new recipient will receive
     */
    function addDistributionRecipient(address _destination, uint256 _allocationPoints, uint256 _allocationFee)
        external
        onlyRole(GOVERNANCE)
    {
        _validateRecipientConfig(_destination, _allocationPoints, _allocationFee);

        distributeRewards();

        RecipientData memory recipient = RecipientData(_destination, _allocationPoints, _allocationFee);

        /// Update total token allocation
        totalAllocationPoints = totalAllocationPoints + _allocationPoints;

        /// Update total fee allocation
        totalAllocationFee = totalAllocationFee + _allocationFee;

        /// Push data into RecipientData array
        recipients.push(recipient);

        emit AddRecipient(recipients.length - 1, _destination, _allocationPoints, _allocationFee);
    }

    /**
     * @notice Allows owner to remove a recipient from the RecipientData array
     * @param index The index of the recipient to be removed
     */
    function removeDistributionRecipient(uint256 index) external onlyRole(GOVERNANCE) {
        require(index <= recipients.length - 1, Errors.VE_INVALID_INDEX);

        distributeRewards();

        /// Update total token allocation
        totalAllocationPoints = totalAllocationPoints - recipients[index].allocationPoints;

        /// Update total fee allocation
        totalAllocationFee = totalAllocationFee - recipients[index].allocationFee;

        /// shift distributions indexes across
        for (uint256 i = index; i < recipients.length - 1; i++) {
            recipients[i] = recipients[i + 1];
        }
        recipients.pop();
    }

    /**
     * @notice Allows owner to edit details of a recipient in the RecipientData array
     * @notice Only callable by the Governance role.
     * @param _index The index of the recipient to edit.
     * @param _destination The address of the new recipient
     * @param _allocationPoints The number of allocation points the new recipient will receive
     * @param _allocationFee The amount of fees the new recipient will receive
     */
    function editDistributionRecipient(
        uint256 _index,
        address _destination,
        uint256 _allocationPoints,
        uint256 _allocationFee
    ) external onlyRole(GOVERNANCE) {
        _validateRecipientConfig(_destination, _allocationPoints, _allocationFee);
        require(_index <= recipients.length - 1, Errors.VE_INVALID_INDEX);

        distributeRewards();

        /// Update destination
        recipients[_index].destination = _destination;

        /// Update total token allocation
        totalAllocationPoints = totalAllocationPoints - recipients[_index].allocationPoints + _allocationPoints;

        /// Update total fee allocation
        totalAllocationFee = totalAllocationFee - recipients[_index].allocationFee + _allocationFee;

        /// Update allocations
        recipients[_index].allocationPoints = _allocationPoints;
        recipients[_index].allocationFee = _allocationFee;

        emit EditRecipient(_index, _destination, _allocationPoints, _allocationFee);
    }

    /**
     * @notice Allows the owner to set the rewards per second.
     * @notice Only callable by the Governance role.
     * @param _newRewardsPerSecond The new rewards per second.
     */
    function setRewardsPerSecond(uint256 _newRewardsPerSecond) external onlyRole(GOVERNANCE) {
        distributeRewards();

        rewardsPerSecond = _newRewardsPerSecond;
        emit RewardsPerSecondUpdate(rewardsPerSecond);
    }

    /// <=============== VIEWS ===============>
    /**
     * @notice Returns an array of all recipients.
     * @return An array of all recipients.
     */
    function getRecipients() public view returns (RecipientData[] memory) {
        return recipients;
    }

    /// <=============== PRIVATE ===============>
    /**
     * @dev validates that the recipient:
     * - destination is not a zero address
     * - either allocationPoints and allocationFee is a non-zero value
     * @param _destination - the recipient destination address
     * @param _allocationPoints - the recipient Struct token allocation
     * @param _allocationFee - the recipient native token allocation
     *
     */
    function _validateRecipientConfig(address _destination, uint256 _allocationPoints, uint256 _allocationFee)
        public
        pure
    {
        require(_allocationPoints != 0 || _allocationFee != 0, Errors.VE_INVALID_ALLOCATION);
        require(_destination != address(0), Errors.AE_ZERO_ADDRESS);
    }
}
