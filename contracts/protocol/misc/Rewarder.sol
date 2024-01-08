// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

/// External imports
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// Internal Imports
import {IFEYProduct} from "../../interfaces/IFEYProduct.sol";
import {CustomReentrancyGuard} from "../../utils/CustomReentrancyGuard.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Constants} from "../libraries/helpers/Constants.sol";
import {IStructPriceOracle} from "../../interfaces/IStructPriceOracle.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {GACManaged} from "../common/GACManaged.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {Helpers} from "../libraries/helpers/Helpers.sol";
import {WadMath} from "../../utils/WadMath.sol";

/**
 * @dev Rewarder contract will allow addresses with a REWARDER role to
 * allocate reward tokens to addresses with PRODUCT roles. These roles
 * are managed by the GAC contract.
 *
 * Rewards are only allocated to investors whose deposits are invested and
 * whose tranche has been allocated rewards.
 * Rewards can either be distributed immediately or at maturity.
 * This contract supports any ERC20 token as a reward token.
 */

contract Rewarder is CustomReentrancyGuard, GACManaged {
    using SafeERC20 for IERC20Metadata;
    using WadMath for uint256;

    /// @notice Contains a reward token's allocation details for a product address
    /// @dev It is populated during reward allocation
    struct AllocationDetails {
        /// amount of reward allocated to the senior tranche
        uint256 rewardSr;
        /// amount of reward allocated to the junior tranche
        uint256 rewardJr;
        /// amount of reward claimed from the senior tranche
        uint256 claimedSr;
        /// amount of reward claimed from the junior tranche
        uint256 claimedJr;
        /// whether rewards can be distributed immediately or must wait till maturity
        bool immediateDistribution;
    }

    /// @notice Contains an investor's claim details for a product and reward token
    /// @dev It is populated during claiming of rewards
    struct InvestorDetails {
        /// amount of reward claimed from the senior tranche
        uint256 claimedSr;
        /// amount of reward claimed from the junior tranche
        uint256 claimedJr;
    }

    /// @dev StructPriceOracle Interface
    IStructPriceOracle public structPriceOracle;

    bytes32 internal constant REWARDER = keccak256("REWARDER");

    /// @dev product address => reward address => allocation details
    mapping(address => mapping(address => AllocationDetails)) public allocationDetails;

    /// @dev investor address => product address => reward address => uint256
    mapping(address => mapping(address => mapping(address => InvestorDetails))) public investorDetails;

    /**
     * @notice Emitted whenever rewards are allocated to the product
     * @param product The address of the product contract
     * @param rewardToken The address of the reward token
     * @param rewardSr The amount of reward tokens allocated to senior tranche
     * @param rewardJr The amount of reward tokens allocated to junior tranche
     * @param immediateDistribution Whether the rewards should be distributed immediately or at maturity
     */
    event RewardAllocated(
        address indexed product,
        address indexed rewardToken,
        uint256 rewardSr,
        uint256 rewardJr,
        bool immediateDistribution
    );

    /**
     * @notice Emitted whenever rewards are allocated to the product
     * @param product The address of the product contract
     * @param rewardToken The address of the reward token
     * @param investor The address of the investor
     * @param claimedSr The amount of reward tokens claimed from the senior tranche by the investor
     * @param claimedJr The amount of reward tokens claimed from the junior tranche by the investor
     */
    event RewardClaimed(
        address indexed product,
        address indexed rewardToken,
        address indexed investor,
        uint256 claimedSr,
        uint256 claimedJr
    );

    /**
     * @notice Emitted whenever rewards are rescued by REWARDER
     * @param product The address of the product contract
     * @param rewardToken The address of the reward token
     * @param amount The amount of tokens rescued
     */
    event TokensRescued(address indexed product, address indexed rewardToken, uint256 amount);

    constructor(IGAC _globalAccessControl, IStructPriceOracle _priceOracle) {
        __GACManaged_init(_globalAccessControl);
        structPriceOracle = _priceOracle;
    }

    /**
     * @notice Allocates _rewardToken tokens to a _product contract
     * @dev Can only be called by the REWARDER role
     * @dev The contract should not be in the `PAUSED` state
     * @param _feyProduct The product contract
     * @param _rewardToken The address of the reward token
     * @param _rewardSrAPR The APR to allocate to the senior tranche in fixed point
     * @param _rewardJrAPR The APR to allocate to the junior tranche in fixed point
     * @param _immediateDistribution Whether the rewards should be distributed immediately or at maturity
     */
    function allocateRewards(
        IFEYProduct _feyProduct,
        address _rewardToken,
        uint256 _rewardSrAPR,
        uint256 _rewardJrAPR,
        bool _immediateDistribution
    ) external nonReentrant gacPausable onlyRole(REWARDER) {
        _validateAllocateRewards(_feyProduct, _rewardToken, _rewardSrAPR, _rewardJrAPR);

        /// return values are in token decimals
        (uint256 _rewardSr, uint256 _rewardJr) = calculateRewards(_feyProduct, _rewardToken, _rewardSrAPR, _rewardJrAPR);

        AllocationDetails storage _allocationDetails = allocationDetails[address(_feyProduct)][_rewardToken];
        /// Update _rewardSr and _rewardJr based on rewards received,
        /// and according to their previous proportion
        uint256 _balanceBefore = IERC20Metadata(_rewardToken).balanceOf(address(this));
        uint256 _rewardTotal = _rewardSr + _rewardJr;
        IERC20Metadata(_rewardToken).safeTransferFrom(_msgSender(), address(this), _rewardTotal);
        uint256 _rewardsReceived = IERC20Metadata(_rewardToken).balanceOf(address(this)) - _balanceBefore;
        _rewardSr = _rewardSr.mulDiv(_rewardsReceived, _rewardTotal);
        _rewardJr = _rewardJr.mulDiv(_rewardsReceived, _rewardTotal);

        /// Update allocationDetails
        _allocationDetails.rewardSr += _rewardSr;
        _allocationDetails.rewardJr += _rewardJr;
        _allocationDetails.immediateDistribution = _immediateDistribution;

        emit RewardAllocated(address(_feyProduct), _rewardToken, _rewardSr, _rewardJr, _immediateDistribution);
    }

    /**
     * @notice Allows investors to claim eligible rewards for a product, for both tranches
     * @dev The contract should not be in the `PAUSED` state
     * @param _product The address of the product contract
     * @param _rewardToken The address of the reward token
     */
    function claimRewards(address _product, address _rewardToken) external nonReentrant gacPausable {
        IFEYProduct feyProduct = IFEYProduct(_product);
        DataTypes.State _currentState = feyProduct.getCurrentState();
        DataTypes.TrancheInfo memory _trancheInfoSr = feyProduct.getTrancheInfo(DataTypes.Tranche.Senior);
        DataTypes.TrancheInfo memory _trancheInfoJr = feyProduct.getTrancheInfo(DataTypes.Tranche.Junior);

        (uint256 _userInvestedSr,) = feyProduct.getUserInvestmentAndExcess(DataTypes.Tranche.Senior, _msgSender());
        (uint256 _userInvestedJr,) = feyProduct.getUserInvestmentAndExcess(DataTypes.Tranche.Junior, _msgSender());
        InvestorDetails memory _investorDetails = investorDetails[_msgSender()][_product][_rewardToken];
        AllocationDetails memory _allocationDetails = allocationDetails[_product][_rewardToken];

        /// Can only claim if tranche has rewards
        require(_allocationDetails.rewardSr > 0 || _allocationDetails.rewardJr > 0, Errors.VE_REWARDER_NO_ALLOCATION);

        if (!_allocationDetails.immediateDistribution) {
            /// If rewards are not eligible for immediate distribution,
            /// funds in the product must have already been withdrawn before rewards can be claimed
            require(_currentState == DataTypes.State.WITHDRAWN, Errors.VE_INVALID_STATE);
        }

        /// User can only claim rewards if they have funds invested, and have not already claimed
        /// We do not need to check for excess since we are already finding the amount users have invested
        require(_userInvestedSr > 0 || _userInvestedJr > 0, Errors.VE_REWARDER_NOT_ELIGIBLE);

        /// Amount to allocate to the user is proportionate to the amount the user invested, and
        /// the amount of tokens invested by the tranche
        uint256 _claimableSr = _allocationDetails.rewardSr.mulDiv(_userInvestedSr, _trancheInfoSr.tokensInvestable);

        uint256 _claimableJr = _allocationDetails.rewardJr.mulDiv(_userInvestedJr, _trancheInfoJr.tokensInvestable);

        uint256 _claimedTotal = _investorDetails.claimedSr + _investorDetails.claimedJr;

        /// We allow users to claim again in the event allocateRewards is called multiple times
        /// We allow this by tracking the total amount claimed by the user for the product and reward token
        /// And allowing the user to claim the difference between the total amount allocated and the total amount claimed
        require(_claimableSr + _claimableJr > _claimedTotal, Errors.VE_REWARDER_INSUFFICIENT_ALLOCATION);

        /// We increment the total reward tokens claimed by the user for the product
        allocationDetails[_product][_rewardToken].claimedSr += _claimableSr - _investorDetails.claimedSr;
        allocationDetails[_product][_rewardToken].claimedJr += _claimableJr - _investorDetails.claimedJr;

        /// Update total claimed by the user for senior and junior tranche
        investorDetails[_msgSender()][_product][_rewardToken].claimedSr = _claimableSr;
        investorDetails[_msgSender()][_product][_rewardToken].claimedJr = _claimableJr;

        /// We transfer the amount claimable by the user
        IERC20Metadata(_rewardToken).safeTransfer(_msgSender(), _claimableSr + _claimableJr - _claimedTotal);

        /// We emit the amount claimed by the user, not the total amount allocated to the user
        emit RewardClaimed(
            _product,
            _rewardToken,
            _msgSender(),
            _claimableSr - _investorDetails.claimedSr,
            _claimableJr - _investorDetails.claimedJr
        );
    }

    /**
     * @notice Allows REWARDER to rescue reward tokens
     * @dev The contract should not be in the `PAUSED` state
     * @param _product The address of the product contract
     * @param _rewardToken The address of the reward token
     */
    function rescueTokens(address _product, address _rewardToken) external nonReentrant onlyRole(REWARDER) {
        AllocationDetails memory _allocationDetails = allocationDetails[_product][_rewardToken];

        /// Can only claim if product has been allocated rewards
        require(_allocationDetails.rewardSr > 0 || _allocationDetails.rewardJr > 0, Errors.VE_REWARDER_NO_ALLOCATION);

        /// Identify amount that has not been claimed for senior tranche and junior tranche
        /// We do this to ensure that we do not rescue tokens that have been allocated to other products
        uint256 _amount = (_allocationDetails.rewardSr + _allocationDetails.rewardJr)
            - (_allocationDetails.claimedSr + _allocationDetails.claimedJr);

        /// refresh allocationDetails for product and reward token pair
        delete allocationDetails[_product][_rewardToken];

        IERC20Metadata(_rewardToken).safeTransfer(_msgSender(), _amount);

        emit TokensRescued(_product, _rewardToken, _amount);
    }

    /**
     * @notice Calculate the amount of rewards to allocate to senior and/or junior tranche
     * @param _feyProduct The product contract
     * @param _rewardToken The address of the reward token
     * @param _rewardSrAPR The APR to allocate to the senior tranche in fixed point
     * @param _rewardJrAPR The APR to allocate to the junior tranche in fixed point
     */
    function calculateRewards(IFEYProduct _feyProduct, address _rewardToken, uint256 _rewardSrAPR, uint256 _rewardJrAPR)
        public
        view
        returns (uint256 rewardSr, uint256 rewardJr)
    {
        DataTypes.ProductConfig memory _productConfig = _feyProduct.getProductConfig();
        uint256 _duration = _productConfig.endTimeTranche - _productConfig.startTimeTranche;
        uint256 _rewardPriceUSD = structPriceOracle.getAssetPrice(_rewardToken);
        uint256 _rewardDecimals = IERC20Metadata(_rewardToken).decimals();

        if (_rewardSrAPR > 0) {
            rewardSr = Helpers.weiToTokenDecimals(
                _rewardDecimals,
                _calculateRewardForTranche(
                    _feyProduct, _rewardSrAPR, _rewardPriceUSD, _duration, DataTypes.Tranche.Senior
                )
            );
        }

        if (_rewardJrAPR > 0) {
            rewardJr = Helpers.weiToTokenDecimals(
                _rewardDecimals,
                _calculateRewardForTranche(
                    _feyProduct, _rewardJrAPR, _rewardPriceUSD, _duration, DataTypes.Tranche.Junior
                )
            );
        }
    }

    /**
     * @notice Calculate the amount of rewards to allocate to a tranche
     * @param _feyProduct The product contract
     * @param _rewardAPR The APR to allocate to the tranche in fixed point
     * @param _rewardPriceUSD The price of the reward token in wei
     * @param _duration The term of the product
     * @param _tranche The tranche - junior or senior
     * @return _rewardAllocation The amount of rewards to allocate to the tranche
     */
    function _calculateRewardForTranche(
        IFEYProduct _feyProduct,
        uint256 _rewardAPR,
        uint256 _rewardPriceUSD,
        uint256 _duration,
        DataTypes.Tranche _tranche
    ) internal view returns (uint256 _rewardAllocation) {
        DataTypes.TrancheInfo memory _trancheInfo = _feyProduct.getTrancheInfo(_tranche);
        DataTypes.TrancheConfig memory _trancheConfig = _feyProduct.getTrancheConfig(_tranche);

        uint256 _tranchePrice = structPriceOracle.getAssetPrice(address(_trancheConfig.tokenAddress));

        /// We will calculate the amount to allocate base on the following formula:
        /// allocation = (APR * tokensInvestableUSD * duration) / (rewardPriceUSD * 1 year)
        _rewardAllocation = (
            _rewardAPR * _duration * _trancheInfo.tokensInvestable.mulDiv(_tranchePrice, _rewardPriceUSD)
        ) / (Constants.DECIMAL_FACTOR * Constants.YEAR_IN_SECONDS);
    }

    /**
     * @notice Runs validations for allocateRewards.
     * @param _feyProduct The product contract
     * @param _rewardToken The address of the reward token
     * @param _rewardSrAPR The APR to allocate to the senior tranche in fixed point
     * @param _rewardJrAPR The APR to allocate to the junior tranche in fixed point
     */
    function _validateAllocateRewards(
        IFEYProduct _feyProduct,
        address _rewardToken,
        uint256 _rewardSrAPR,
        uint256 _rewardJrAPR
    ) internal view {
        require(_rewardSrAPR > 0 || _rewardJrAPR > 0, Errors.VE_REWARDER_INVALID_APR);
        /// Only can allocate rewards to FEYProducts
        require(gac.hasRole(PRODUCT, address(_feyProduct)), Errors.ACE_INVALID_ACCESS);
        require(_rewardToken != address(0), Errors.AE_ZERO_ADDRESS);

        /// We only allow allocation to products in INVESTED state since:
        /// 1. we can't know how much funds will be invested ex-ante
        /// 2. we can't know how much funds would have been withdrawn by users before we make the allocation ex-post
        require(_feyProduct.getCurrentState() == DataTypes.State.INVESTED, Errors.VE_INVALID_STATE);
    }

    /**
     * @notice Get allocation details of a product and reward token
     * @param _product The address of the product contract
     * @param _rewardToken The address of the reward token
     */
    function getAllocationDetails(address _product, address _rewardToken)
        public
        view
        returns (AllocationDetails memory)
    {
        return allocationDetails[_product][_rewardToken];
    }
}
