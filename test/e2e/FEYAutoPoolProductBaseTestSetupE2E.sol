// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@external/traderjoe/IStrategy.sol";
import "@external/traderjoe/IAPTFarm.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../common/fey-products/autopool/AutoPoolProductBaseTestSetupLive.sol";
import {Helpers} from "@core/libraries/helpers/Helpers.sol";

contract FEYAutoPoolProductBaseTestSetupE2E is AutoPoolProductBaseTestSetupLive {
    enum UserAction {
        EXCESS_CLAIM,
        WITHDRAW
    }

    struct UserDeposit {
        FEYProductUser user;
        uint256 amount;
        DataTypes.Tranche tranche;
        IERC20Metadata token;
        bool isNative;
    }

    uint256 public wavaxToDeposit = 100e18;
    uint256 public eurocToDeposit = 1898e6;
    uint256 public usdcToDeposit = 2000e6;

    uint256 public usdcValueDecimalScalingFactor = 1e12;

    /////////////////
    /// Assertions //
    /////////////////

    // asserts that the product's tranche token balance decreases by the expected excess or withdrawal amount
    modifier assertTrancheTokensTransferredEqualsExcessAndOrWithdrawn(
        FEYProductUser _user,
        DataTypes.Tranche _tranche,
        IERC20Metadata _token,
        UserAction _actionType
    ) {
        sut.recordTrancheTokenBalance(_token, true);
        uint256 _userExcessAndOrWithdrawalAmount = _getUserExcessAndOrWithdrawalAmount(_user, _tranche, _actionType);
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        console.log("::ASSERT:: for %s tranche token (%s):", _getTrancheName(_tranche), _token.symbol());
        console.log(
            "product's token balance decreases by expected %s amount: %s",
            _getUserAction(_actionType),
            _userExcessAndOrWithdrawalAmount / Constants.WAD
        );
        uint256 _trancheBalanceAfter = _token.balanceOf(address(sut));
        assertEq(
            sut.trancheTokenBalanceBefore(address(_token)) - _token.balanceOf(address(sut)),
            Helpers.weiToTokenDecimals(IERC20Metadata(_token).decimals(), _userExcessAndOrWithdrawalAmount)
        );
        assertGt(_userExcessAndOrWithdrawalAmount, 0);
    }

    // asserts that the users AVAX balance increases by the same amount of wAVAX leaving the product contract
    modifier assertTrancheTokenDeltaEqualsInvestorTokenReceived(
        FEYProductUser _user,
        DataTypes.Tranche _tranche,
        IERC20Metadata _token,
        UserAction _actionType
    ) {
        DataTypes.Investor memory _investorDetails = sut.getInvestorDetails(_tranche, address(_user));
        if (_investorDetails.depositedNative) {
            _user.recordAvaxBalance(true);
            sut.recordTrancheTokenBalance(_token, true);
            /// EXECUTE LOGIC
            _;
            /// LOGIC EXECUTED
            _lineBreak();
            console.log(
                "::ASSERT:: product's %s tranche token balance decreases by amount of AVAX received by investor on %s",
                _getTrancheName(_tranche),
                _getUserAction(_actionType)
            );
            _user.recordAvaxBalance(false);
            sut.recordTrancheTokenBalance(_token, false);
            assertEq(
                sut.trancheTokenBalanceBefore(address(_token)) - sut.trancheTokenBalanceAfter(address(_token)),
                _user.avaxBalanceAfter() - _user.avaxBalanceBefore()
            );
            assertGt(_user.avaxBalanceAfter(), _user.avaxBalanceBefore());
        } else {
            _user.recordTrancheTokenBalance(_token, true);
            sut.recordTrancheTokenBalance(_token, true);
            /// EXECUTE LOGIC
            _;
            /// LOGIC EXECUTED
            _lineBreak();
            console.log(
                "::ASSERT:: product's %s tranche token balance decreases by amount received by investor on %s",
                _getTrancheName(_tranche),
                _getUserAction(_actionType)
            );
            _user.recordTrancheTokenBalance(_token, false);
            sut.recordTrancheTokenBalance(_token, false);

            assertEq(
                sut.trancheTokenBalanceBefore(address(_token)) - sut.trancheTokenBalanceAfter(address(_token)),
                _user.trancheTokenBalanceAfter(address(_token)) - _user.trancheTokenBalanceBefore(address(_token))
            );
            assertGt(_user.trancheTokenBalanceAfter(address(_token)), _user.trancheTokenBalanceBefore(address(_token)));
        }
    }

    modifier assertPostUserWithdrawalBalances(FEYProductUser _user, DataTypes.Tranche _tranche) {
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        console.log("::ASSERT:: user %s SP token balance is 0 post-withdrawal", address(_user));
        assertEq(spToken.balanceOf(address(_user), uint256(_tranche)), 0);
    }

    modifier assertPostAllWithdrawalsSpTokenSupply(DataTypes.Tranche _tranche) {
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        console.log("::ASSERT:: SP totalSupply is 0 for ID %s post all withdrawals", uint256(_tranche));
        assertEq(spToken.totalSupply(uint256(_tranche)), 0);
    }

    // asserts that the product's status is correctly updated
    modifier assertValidProductState(DataTypes.State _state) {
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        console.log("::ASSERT:: product state should be %s", uint256(_state));
        assertEq(uint8(sut.getCurrentState()), uint8(_state));
    }

    // asserts that the variable `isQueuedForWithdrawal` is set to the expected value
    modifier assertIsQueuedForWithdrawalState(uint8 _isQueuedForWithdrawal) {
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        console.log("::ASSERT:: isQueuedForWithdrawal should be %s", _isQueuedForWithdrawal);
        assertEq(uint8(sut.isQueuedForWithdrawal()), _isQueuedForWithdrawal);
    }

    modifier assertNoDustInProduct(
        AutoPoolProductHarness _contract,
        DataTypes.Tranche _tranche,
        bool _accountForExcess
    ) {
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        DataTypes.TrancheConfig memory _trancheConfig = _contract.getTrancheConfig(_tranche);
        console.log(
            "::ASSERT:: no %s dust should be in product: %s", _trancheConfig.tokenAddress.symbol(), address(_contract)
        );
        DataTypes.TrancheInfo memory _trancheInfo = _contract.getTrancheInfo(_tranche);
        if (_accountForExcess && _trancheInfo.tokensExcess > 0) {
            assertEq(
                _trancheConfig.tokenAddress.balanceOf(address(_contract)),
                Helpers.weiToTokenDecimals(_trancheConfig.decimals, _trancheInfo.tokensExcess)
            );
        } else {
            assertEq(_trancheConfig.tokenAddress.balanceOf(address(_contract)), 0);
        }
    }

    modifier assertNoDustInYieldSource(IAutoPoolYieldSource _contract, bool _includingAptFarm) {
        /// EXECUTE LOGIC
        _;
        /// LOGIC EXECUTED
        _lineBreak();
        IERC20Metadata _tokenA = _contract.tokenA();
        console.log("::ASSERT:: no %s dust should be in yield source: %s", _tokenA.symbol(), address(_contract));
        assertEq(_tokenA.balanceOf(address(_contract)), 0);
        IERC20Metadata _tokenB = _contract.tokenB();
        console.log("::ASSERT:: no %s dust should be in yield source: %s", _tokenB.symbol(), address(_contract));
        assertEq(_tokenA.balanceOf(address(_contract)), 0);
        IAutoPoolVault _autoPoolVault = _contract.autoPoolVault();
        console.log("::ASSERT:: no %s dust should be in yield source: %s", _autoPoolVault.symbol(), address(_contract));
        assertEq(_autoPoolVault.balanceOf(address(_contract)), 0);

        if (_includingAptFarm) {
            IAPTFarm _aptFarm = IAPTFarm(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C);
            uint256 _aptFarmId = _aptFarm.vaultFarmId(address(_autoPoolVault));
            IAPTFarm.UserInfo memory _userInfo = _aptFarm.userInfo(_aptFarmId, address(_contract));
            console.log(
                "::ASSERT:: no %s dust should be in farm for yield source: %s",
                _autoPoolVault.symbol(),
                address(_contract)
            );
            assertEq(_userInfo.amount, 0);
        }
    }

    modifier logInvestedAndExcess(DataTypes.Tranche _tranche) {
        _;
        DataTypes.TrancheInfo memory _trancheInfo = sut.getTrancheInfo(_tranche);
        _lineBreak();
        console.log("%s tranche INVESTED info", _getTrancheName(_tranche));
        console.log("Invested: %s", _trancheInfo.tokensInvested / Constants.WAD);
        console.log("Excess: %s", _trancheInfo.tokensExcess / Constants.WAD);
    }

    modifier logTokensReceivedAndAllocated(DataTypes.Tranche _tranche) {
        _;
        DataTypes.TrancheInfo memory _trancheInfo = sut.getTrancheInfo(_tranche);
        _lineBreak();
        console.log("%s tranche MATURED info", _getTrancheName(_tranche));
        console.log("Tokens received from LP: %s", _trancheInfo.tokensReceivedFromLP / Constants.WAD);
        console.log("Tokens allocated to tranche: %s", _trancheInfo.tokensAtMaturity / Constants.WAD);
    }

    modifier logUserInvestedAndExcess(UserDeposit[] memory _userDeposits) {
        _;
        // to correctly label the user number in the logs
        uint256 _userNumber = 0;
        address _lastAddress = address(0);
        for (uint256 i = 0; i < _userDeposits.length; i++) {
            UserDeposit memory _userDeposit = _userDeposits[i];
            // if user address is same as last iteration, userNumber is the same
            if (_lastAddress != address(_userDeposit.user)) {
                _userNumber++;
                _lineBreak();
                (uint256 _investment, uint256 _excess) =
                    sut.getUserInvestmentAndExcess(_userDeposit.tranche, address(_userDeposit.user));
                console.log("User %s: %s", _userNumber, address(_userDeposit.user));
                console.log("%s tranche (%s)", _getTrancheName(_userDeposit.tranche), _userDeposit.token.symbol());
                console.log("Invested: %s", _investment / Constants.WAD);
                console.log("Excess: %s", _excess / Constants.WAD);
            }
            _lastAddress = address(_userDeposit.user);
        }
    }

    /////////////////
    /// Helpers /////
    /////////////////

    function _getUserExcessAndOrWithdrawalAmount(
        FEYProductUser _user,
        DataTypes.Tranche _tranche,
        UserAction _actionType
    ) internal view returns (uint256) {
        if (_actionType == UserAction.WITHDRAW) {
            return _calculateUserShare(address(_user), _tranche, 0, true);
        }
        DataTypes.Investor memory _investorDetails = sut.getInvestorDetails(_tranche, address(_user));
        (, uint256 _userExcess) = sut.getUserInvestmentAndExcess(_tranche, address(_user));
        if (_actionType == UserAction.EXCESS_CLAIM) {
            if (_investorDetails.claimed) {
                return 0;
            }
            return _userExcess;
        }
        return 0;
    }

    function _calculateUserShare(
        address _user,
        DataTypes.Tranche _tranche,
        uint256 _excessSpAmount,
        bool _hasClaimedExcess
    ) internal view returns (uint256) {
        DataTypes.TrancheInfo memory _trancheInfo = sut.getTrancheInfo(_tranche);
        DataTypes.TrancheConfig memory _trancheConfig = sut.getTrancheConfig(_tranche);
        uint256 _userSpTokenBalance = spToken.balanceOf(_user, _trancheConfig.spTokenId);
        if (!_hasClaimedExcess) {
            _userSpTokenBalance -= _excessSpAmount;
        }
        return (_trancheInfo.tokensAtMaturity * _userSpTokenBalance) / _trancheInfo.tokensInvestable;
    }

    function _getTotalSupplySpToken(DataTypes.Tranche _tranche) internal view returns (uint256) {
        return spToken.totalSupply(uint256(_tranche));
    }

    function _simulateExecuteQueuedWithdrawals(IAutoPoolVault _autoPoolVault) internal {
        IStrategy strategy = IStrategy(_autoPoolVault.getStrategy());

        address defaultOperator = address(0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2);
        vm.startPrank(defaultOperator);
        strategy.rebalance(0, 0, 0, 0, 0, 0, new bytes(0));
        vm.stopPrank();
    }

    function _getTrancheName(DataTypes.Tranche _tranche) internal pure returns (string memory) {
        if (_tranche == JUNIOR_TRANCHE) {
            return "junior";
        }
        return "senior";
    }

    function _getUserAction(UserAction _userAction) internal pure returns (string memory) {
        if (_userAction == UserAction.EXCESS_CLAIM) {
            return "claimExcess";
        }
        if (_userAction == UserAction.WITHDRAW) {
            return "withdraw";
        }
        return "!!!NOT FOUND!!!";
    }

    function _lineBreak() internal view {
        console.log("--------------------------------------------------");
    }
}
