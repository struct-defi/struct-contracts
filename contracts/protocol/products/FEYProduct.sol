// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Internal Imports
import {CustomReentrancyGuard} from "../../utils/CustomReentrancyGuard.sol";
import {ISPToken} from "../../interfaces/ISPToken.sol";
import {IFEYProduct} from "../../interfaces/IFEYProduct.sol";
import {IStructPriceOracle} from "../../interfaces/IStructPriceOracle.sol";
import {IDistributionManager} from "../../interfaces/IDistributionManager.sol";
import {IWETH9} from "../../external/IWETH9.sol";

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Helpers} from "../libraries/helpers/Helpers.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {Validation} from "../libraries/logic/Validation.sol";
import {GACManaged} from "../common/GACManaged.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {WadMath} from "../../utils/WadMath.sol";

/**
 * @title Fixed and Enhanced Yield AutoPool Product contract
 * @notice Main point of interaction with the FEY product contract
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Claim Excess
 *
 * @author Struct Finance
 */

abstract contract FEYProduct is IFEYProduct, CustomReentrancyGuard, GACManaged {
    using SafeERC20 for IERC20Metadata;
    using WadMath for uint256;

    /// @dev Helps to identify the current state of the product
    DataTypes.State internal currentState;

    /// @dev Configuration for the current product
    DataTypes.ProductConfig internal productConfig;

    /// @dev Address of the Native token
    address payable public nativeToken;

    /// @dev Address of the Product Factory contract
    address public productFactory;

    /// @dev Initializer flag
    bool internal isInitialized;

    /// @dev Total Fee Senior
    uint256 public feeTotalSr;

    /// @dev Total Fee Junior
    uint256 public feeTotalJr;

    /// @dev DistributionManager Interface
    IDistributionManager public distributionManager;

    /// @dev StructPriceOracle Interface
    IStructPriceOracle public structPriceOracle;

    /// @dev The address of the Struct SP Token
    ISPToken public spToken;

    /// @dev Tranche id => user address => deposits
    mapping(DataTypes.Tranche => mapping(address => DataTypes.Investor)) internal investors;

    /// @dev Contains the info specific to senior and junior tranches
    mapping(DataTypes.Tranche => DataTypes.TrancheInfo) internal trancheInfo;

    /// @dev Contains the specifications of senior and junior tranches
    mapping(DataTypes.Tranche => DataTypes.TrancheConfig) internal trancheConfig;

    uint256 internal _srDecimals;
    uint256 internal _jrDecimals;

    /**
     * @notice Allows users to deposit their funds into the tranche.
     * @dev Assets will be held by the contract until the predetermined investment start time.
     * @param _tranche The tranche into which the assets should be deposited
     * @param _amount The amount of tokens that needs to be deposited into the tranche
     */
    function deposit(DataTypes.Tranche _tranche, uint256 _amount) external payable override nonReentrant gacPausable {
        _deposit(_tranche, _amount, _msgSender());
    }

    /**
     * @notice Allows users to deposit their funds into the tranche.
     * @dev Assets will be held by the contract until the predetermined investment start time.
     * @param _tranche The tranche into which the assets should be deposited
     * @param _amount The amount of tokens that needs to be deposited into the tranche
     * @param _onBehalfOf The address of the beneficiary wallet that should recieve StructSPToken
     */
    function depositFor(DataTypes.Tranche _tranche, uint256 _amount, address _onBehalfOf)
        external
        payable
        override
        nonReentrant
        gacPausable
        onlyRole(FACTORY)
    {
        _deposit(_tranche, _amount, _onBehalfOf);
    }

    /**
     * @notice Allows users to claim any excess tokens, and returns their corresponding amount of tokens in return for their SP tokens.
     * @param _tranche The tranche from which the excess tokens to be claimed
     */
    function claimExcess(DataTypes.Tranche _tranche) external override nonReentrant gacPausable {
        (uint256 _userInvested, uint256 _excess) =
            Validation.validateClaimExcess(currentState, investors[_tranche][_msgSender()], trancheInfo[_tranche]);
        _claimExcess(_tranche, _userInvested, _excess);
    }

    /**
     * @notice Allows a user to withdraw the investment from the product once the tranche is matured
     * @param _tranche The tranche id from which the investment should be withdrawn
     */
    function withdraw(DataTypes.Tranche _tranche) external override nonReentrant gacPausable {
        Validation.validateWithdrawal(
            currentState,
            spToken,
            trancheConfig[_tranche].spTokenId,
            investors[_tranche][_msgSender()],
            trancheInfo[_tranche].tokensInvestable
        );
        _calculateUserShareAndTransfer(_tranche);
    }

    /**
     * @notice Used to withdraw any funds thats left in the contract
     * @dev It can be called only by the Governance in case of emergency
     * @param _token The address of the token to be withdrawn
     * @param _recipient The address of the recipient who receives the tokens
     */
    function rescueTokens(IERC20Metadata _token, address _recipient) external onlyRole(GOVERNANCE) {
        _token.safeTransfer(_recipient, Helpers._getTokenBalance(_token, address(this)));
    }

    /**
     * @notice Used to withdraw any funds thats left in the contract
     * @dev Anyone can call this function if the product is not invested after 24 hours from the tranche start time.
     */
    function forceUpdateStatusToWithdrawn() public {
        require(
            currentState == DataTypes.State.OPEN && block.timestamp > (productConfig.startTimeTranche + 24 hours),
            Errors.VE_INVALID_STATE
        );

        _forceUpdateStatusToWithdrawn();
    }

    /**
     * @notice used to find the user investment and excess for the given tranche if any
     * @param _tranche id of the senior/junior tranche
     * @param _investor address of the investor
     * @return userInvested - the share of the user invested that accounts for total investment to the pool
     * @return excess - the share of the user's deposit that was not invested into the pool
     */
    function getUserInvestmentAndExcess(DataTypes.Tranche _tranche, address _investor)
        external
        view
        override
        returns (uint256, uint256)
    {
        if (currentState == DataTypes.State.OPEN) {
            return (0, 0);
        }
        (uint256 userInvested, uint256 excess) =
            Helpers.getInvestedAndExcess(investors[_tranche][_investor], trancheInfo[_tranche].tokensInvestable);

        return (userInvested, excess);
    }

    /**
     * @notice Used to get the total amount of tokens deposited by the user into a given tranche
     * @param _tranche id of the senior/junior tranche
     * @param _investor address of the investor
     * @return userDeposited the total amount of tokens deposited by the user into a given tranche
     */
    function getUserTotalDeposited(DataTypes.Tranche _tranche, address _investor) external view returns (uint256) {
        uint256 length = investors[_tranche][_investor].userSums.length;
        return investors[_tranche][_investor].userSums[length - 1];
    }

    /**
     * @notice Used to get the details of the investor for the given tranche
     * @param _tranche ID of the tranche
     * @param _user Address of the user
     * @return The investor info
     */
    function getInvestorDetails(DataTypes.Tranche _tranche, address _user)
        external
        view
        override
        returns (DataTypes.Investor memory)
    {
        return investors[_tranche][_user];
    }

    /**
     * @notice Used to get the current status of the Product
     * @return The current state of the product
     */
    function getCurrentState() external view override returns (DataTypes.State) {
        return currentState;
    }

    /**
     * @notice Used to get the details of the given tranche
     * @param _tranche ID of the tranche
     * @return Tranche info for the given tranche
     */
    function getTrancheInfo(DataTypes.Tranche _tranche) external view override returns (DataTypes.TrancheInfo memory) {
        return trancheInfo[_tranche];
    }

    /**
     * @notice Used to get the config of the given tranche
     * @param _tranche ID of the tranche
     * @return Tranche config for the given tranche
     */
    function getTrancheConfig(DataTypes.Tranche _tranche)
        external
        view
        override
        returns (DataTypes.TrancheConfig memory)
    {
        return trancheConfig[_tranche];
    }

    /**
     * @notice Used to get the configuration of the product
     */
    function getProductConfig() external view returns (DataTypes.ProductConfig memory) {
        return productConfig;
    }

    /**
     * @notice Deposits the `_amount` to the given `tranche`
     * @param _tranche Senior/Junior Tranche
     * @param _amount The Amount of tokens to be deposited
     * @param _investor The Address under which the deposit has to be recorded
     */
    function _deposit(DataTypes.Tranche _tranche, uint256 _amount, address _investor) internal {
        DataTypes.TrancheConfig memory _trancheConfig = trancheConfig[_tranche];
        DataTypes.TrancheInfo storage _trancheInfo = trancheInfo[_tranche];

        Validation.validateDeposit(
            productConfig.startTimeTranche,
            _trancheConfig.capacity,
            productConfig.startTimeDeposit,
            _trancheInfo.tokensDeposited,
            _amount,
            _trancheConfig.decimals
        );

        DataTypes.Investor storage investor = investors[_tranche][_investor];
        if (msg.value != 0) {
            require(address(_trancheConfig.tokenAddress) == nativeToken, Errors.VE_INVALID_NATIVE_TOKEN_DEPOSIT);
            Helpers._wrapAVAXForDeposit(_amount, nativeToken);
            investor.depositedNative = true;
        } else {
            uint256 tokenBalanceBefore = _trancheConfig.tokenAddress.balanceOf(address(this));
            _trancheConfig.tokenAddress.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = _trancheConfig.tokenAddress.balanceOf(address(this)) - tokenBalanceBefore;
        }

        _amount = Helpers.tokenDecimalsToWei(_trancheConfig.decimals, _amount);

        uint256 _totalDeposited = _trancheInfo.tokensDeposited + _amount;
        _trancheInfo.tokensDeposited = _totalDeposited;
        if (investor.userSums.length == 0) {
            investor.userSums.push(_amount);
        } else {
            investor.userSums.push(_amount + investor.userSums[investor.userSums.length - 1]);
        }

        investor.depositSums.push(_totalDeposited);

        spToken.mint(_investor, _trancheConfig.spTokenId, _amount, "0x0");
        Validation.checkSpAndTrancheTokenBalances(address(this), _tranche, spToken);
        emit Deposited(_tranche, _amount, _investor, _totalDeposited);
    }

    /**
     * @notice Allows users to claim any excess tokens, and returns their corresponding amount of tokens in return for their SP tokens.
     * @param _tranche The tranche id (senior/junior)
     * @param _userInvested The amount the user has invested
     * @param _excess The excess amount the user can claim
     */
    function _claimExcess(DataTypes.Tranche _tranche, uint256 _userInvested, uint256 _excess) private {
        DataTypes.TrancheConfig storage _trancheConfig = trancheConfig[_tranche];

        trancheInfo[_tranche].tokensExcess -= _excess;
        investors[_tranche][_msgSender()].claimed = true;
        spToken.burn(_msgSender(), _trancheConfig.spTokenId, _excess);
        _transferTokens(_trancheConfig, _tranche, _excess);

        emit ExcessClaimed(_tranche, _trancheConfig.spTokenId, _userInvested, _excess, _msgSender());
    }

    /**
     * @notice Transfers either ERC20 or native token to the depositor
     * @param _trancheConfig the configuration of the tranche
     * @param _tranche The tranche id (senior/junior)
     * @param _amount The amount to transfer to the user
     */
    function _transferTokens(
        DataTypes.TrancheConfig storage _trancheConfig,
        DataTypes.Tranche _tranche,
        uint256 _amount
    ) private {
        // if user deposited AVAX to product, unwrap wAVAX and transfer AVAX
        if (investors[_tranche][_msgSender()].depositedNative) {
            IWETH9(nativeToken).withdraw(_amount);
            (bool sent,) = _msgSender().call{value: _amount}("");
            require(sent, Errors.AVAX_TRANSFER_FAILED);
        } else {
            _trancheConfig.tokenAddress.safeTransfer(
                _msgSender(), Helpers.weiToTokenDecimals(_trancheConfig.decimals, _amount)
            );
        }
    }

    /**
     * @notice Calculate the user share from the matured tranche token and transfer to them.
     * @param _tranche The tranche id (senior/junior)
     */
    function _calculateUserShareAndTransfer(DataTypes.Tranche _tranche) internal {
        DataTypes.TrancheInfo storage _trancheInfo = trancheInfo[_tranche];
        DataTypes.TrancheConfig storage _trancheConfig = trancheConfig[_tranche];
        uint256 _userSpTokenBalance = spToken.balanceOf(_msgSender(), _trancheConfig.spTokenId);
        uint256 _userShare = (_trancheInfo.tokensAtMaturity * _userSpTokenBalance) / _trancheInfo.tokensInvestable;

        spToken.burn(_msgSender(), _trancheConfig.spTokenId, _userSpTokenBalance);
        _transferTokens(_trancheConfig, _tranche, _userShare);

        emit Withdrawn(_tranche, _userShare, _msgSender());
    }

    function _forceUpdateStatusToWithdrawn() internal {
        trancheInfo[DataTypes.Tranche.Senior].tokensExcess = trancheInfo[DataTypes.Tranche.Senior].tokensDeposited;
        trancheInfo[DataTypes.Tranche.Junior].tokensExcess = trancheInfo[DataTypes.Tranche.Junior].tokensDeposited;

        currentState = DataTypes.State.WITHDRAWN;
        /// @dev Events to transition product state in the subgraph
        emit Invested(0, 0, 0, 0);
        emit StatusUpdated(DataTypes.State.WITHDRAWN);
        emit RemovedFundsFromLP(0, 0, _msgSender());
    }

    /// @notice To receive native token transfers
    receive() external payable {}

    /*///////////////////////////////////////////////////////////////
                        ABSTRACT METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Product based on the given parameters
     * @dev It should be called only once
     * @param _initConfig Configuration of the tranches and product config
     * @param _structPriceOracle The address of the struct price oracle
     * @param _spToken Address of the Struct SP Token
     * @param _globalAccessControl Address of the StructGAC contract
     * @param _distributionManager Address of the distribution manager contract
     * @param _yieldSource Address of the YieldSource contract
     */
    function initialize(
        DataTypes.InitConfigParam calldata _initConfig,
        IStructPriceOracle _structPriceOracle,
        ISPToken _spToken,
        IGAC _globalAccessControl,
        IDistributionManager _distributionManager,
        address _yieldSource,
        address payable _nativeToken
    ) external virtual override {}

    /**
     * @notice Abstract
     */
    function invest() external virtual override {}

    /**
     * @notice Abstract
     */
    function removeFundsFromLP() external virtual override {}
}
