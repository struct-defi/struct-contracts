// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "./FEYAutoPoolProductBaseTestSetupE2E.sol";

contract FEYAutoPoolProductActions is FEYAutoPoolProductBaseTestSetupE2E {
    /////////////////
    /// Actions /////
    /////////////////

    function handleCreateUserDeposits(
        IERC20Metadata _tokenSr,
        IERC20Metadata _tokenJr,
        uint256 _depositSr,
        uint256 _depositJr
    ) internal virtual returns (UserDeposit[] memory _userDeposits) {
        _userDeposits = new UserDeposit[](2);
        _userDeposits[0] = UserDeposit(user1, _depositSr, SENIOR_TRANCHE, _tokenSr, false);
        _userDeposits[1] = UserDeposit(user2, _depositJr * 2, JUNIOR_TRANCHE, _tokenJr, false);
        return _userDeposits;
    }

    function handleDepositToTranches(UserDeposit[] memory _userDeposits)
        internal
        virtual
        assertValidProductState(DataTypes.State.OPEN)
    {
        // to correctly label the user number in the logs
        uint256 _userNumber = 0;
        address _lastAddress = address(0);
        for (uint256 i = 0; i < _userDeposits.length; i++) {
            UserDeposit memory _userDeposit = _userDeposits[i];
            // if user address is same as last iteration, userNumber is the same
            if (_lastAddress != address(_userDeposit.user)) {
                _userNumber++;
                _lineBreak();
                console.log("User %s address: %s", _userNumber, address(_userDeposit.user));
            }
            _lastAddress = address(_userDeposit.user);

            console.log(
                "User %s depositing %s %s...",
                _userNumber,
                (_userDeposit.amount / 10 ** _userDeposit.token.decimals()),
                _userDeposit.isNative ? "AVAX" : _userDeposit.token.symbol()
            );
            if (_userDeposit.isNative) {
                _depositAvax(_userDeposit.user, _userDeposit.amount, _userDeposit.tranche);
            } else {
                _deposit(_userDeposit.user, _userDeposit.amount, _userDeposit.tranche, _userDeposit.token);
            }
        }
    }

    function handleInvestProduct(UserDeposit[] memory _userDeposits)
        internal
        virtual
        assertValidProductState(DataTypes.State.INVESTED)
        logUserInvestedAndExcess(_userDeposits)
        logInvestedAndExcess(SENIOR_TRANCHE)
        logInvestedAndExcess(JUNIOR_TRANCHE)
        // REMOVED BC THERE IS 1 WEI OF USDC DUST IN EUROC/USDC PRODUCTS
        // assertNoDustInProduct(sut, SENIOR_TRANCHE, true)
        // assertNoDustInProduct(sut, JUNIOR_TRANCHE, true)
        assertNoDustInYieldSource(yieldSource, false)
    {
        _lineBreak();
        console.log("Fast-forwarding to %s", block.timestamp + 15 minutes);
        vm.warp(block.timestamp + 15 minutes);
        console.log("Investing...");
        user1.invest();
    }

    function handleClaimExcess(FEYProductUser _user, DataTypes.Tranche _tranche, IERC20Metadata _token)
        internal
        virtual
        assertTrancheTokenDeltaEqualsInvestorTokenReceived(_user, _tranche, _token, UserAction.EXCESS_CLAIM)
        assertTrancheTokensTransferredEqualsExcessAndOrWithdrawn(_user, _tranche, _token, UserAction.EXCESS_CLAIM)
    {
        _lineBreak();
        console.log("User %s claiming excess", address(_user));
        _user.claimExcess(_tranche);
    }

    function handleWithdraw(FEYProductUser _user, DataTypes.Tranche _tranche, IERC20Metadata _token)
        internal
        virtual
        assertTrancheTokenDeltaEqualsInvestorTokenReceived(_user, _tranche, _token, UserAction.WITHDRAW)
        assertTrancheTokensTransferredEqualsExcessAndOrWithdrawn(_user, _tranche, _token, UserAction.WITHDRAW)
    {
        _lineBreak();
        console.log("User %s withdrawing %s...", address(_user), IERC20Metadata(_token).symbol());
        _user.withdraw(_tranche);
    }

    function handleMockOracleCalls(IAutoPoolVault _autoPoolVault) internal virtual {
        _lineBreak();
        console.log("Fast-forwarding to %s", block.timestamp + 31 days);
        vm.warp(block.timestamp + 31 days);
        console.log("Mocking the chainlink aggregator to return the updatedAt as latest timestamp for the data feeds");
        AggregatorV3Interface oracleX = AggregatorV3Interface(_autoPoolVault.getOracleX());
        AggregatorV3Interface oracleY = AggregatorV3Interface(_autoPoolVault.getOracleY());

        /// Mock the chainlink aggregator to return the updatedAt as latest timestamp for the data feeds
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleX.latestRoundData();

        vm.mockCall(
            address(oracleX),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
        );

        (roundId, answer, startedAt, updatedAt, answeredInRound) = oracleY.latestRoundData();
        vm.mockCall(
            address(oracleY),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
        );
    }

    function handleQueueWithdrawals(IAutoPoolVault _autoPoolVault)
        internal
        virtual
        assertIsQueuedForWithdrawalState(1)
    {
        _lineBreak();
        console.log("Queueing withdrawals...");
        sut.removeFundsFromLP();
        _simulateExecuteQueuedWithdrawals(_autoPoolVault);
    }

    function handleRedeemTokens()
        internal
        virtual
        assertValidProductState(DataTypes.State.WITHDRAWN)
        logTokensReceivedAndAllocated(SENIOR_TRANCHE)
        logTokensReceivedAndAllocated(JUNIOR_TRANCHE)
    {
        _lineBreak();
        console.log("Redeeming tokens...");
        vm.prank(keeper);
        yieldSource.redeemTokens();
    }

    function handleApproveSpToken(FEYProductUser _user) internal virtual {
        _user.setApprovalForAll(IERC1155(address(spToken)), address(sut));
    }

    function handleTransferSpToken(uint256 _spTokenTransferAmount, address _from, address _to) internal virtual {
        _lineBreak();
        console.log(
            "User %s transferring %s SP tokens to user %s",
            address(_from),
            _spTokenTransferAmount / Constants.WAD,
            address(_to)
        );
        user1.setApprovalForAll(IERC1155(address(spToken)), address(_to));
        vm.mockCall(address(factory), abi.encodeWithSelector(IFEYFactory.isTransferEnabled.selector), abi.encode(true));
        vm.prank(address(_to));
        spToken.safeTransferFrom(address(_from), address(_to), uint256(SENIOR_TRANCHE), _spTokenTransferAmount, "");
    }

    function handleForceUpdateStatusToWithdrawn() internal virtual assertValidProductState(DataTypes.State.WITHDRAWN) {
        _lineBreak();
        console.log("Fast-forwarding to %s", block.timestamp + 24 hours);
        vm.warp(block.timestamp + 25 hours);
        console.log("Force withdrawing...");
        sut.forceUpdateStatusToWithdrawn();
    }
}
