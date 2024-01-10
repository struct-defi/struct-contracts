// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@core/libraries/types/DataTypes.sol";
import "./FEYProductBaseTestSetup.sol";

contract WithdrawClaimExcessBaseTestSetup is FEYProductBaseTestSetup {
    uint256 public depositValAVAX = 100e18;

    function setUp() public virtual override {
        super.setUp();
    }

    function _depositWarpInvestJunior(uint256 _amount, bool withAVAX) internal {
        if (withAVAX) {
            user1.depositAvaxToJunior(_amount, _amount);
        } else {
            user1.depositToJunior(_amount);
        }
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();
    }

    function _depositWarpInvestSenior(uint256 _amount, bool withAVAX) internal {
        if (withAVAX) {
            user1.depositAvaxToSenior(_amount, _amount);
        } else {
            user1.depositToSenior(_amount);
        }
        vm.warp(block.timestamp + 15 minutes);

        user1.invest();
    }

    /// @dev gets user and product balances after Method Under Test (MUT) is called
    function getProductAndUserBalancesPostMUT()
        internal
        view
        returns (
            uint256 balTokenProductPostMUT,
            uint256 balTokenUserPostMUT,
            uint256 balAVAXUserPostMUT,
            uint256 balAVAXProductPostMUT
        )
    {
        balTokenProductPostMUT = wavax.balanceOf(address(sut));
        balTokenUserPostMUT = wavax.balanceOf(address(user1));
        balAVAXUserPostMUT = address(user1).balance;
        balAVAXProductPostMUT = address(sut).balance;
    }

    function setProductStateForWithdrawal(DataTypes.Tranche _tranche) internal {
        sut.setExcessClaimed(_tranche, address(user1), true);
        sut.setTokensInvestable(_tranche, depositValAVAX);
        sut.setTokensAtMaturity(_tranche, depositValAVAX);
        user1.setApprovalForAll(IERC1155(address(spToken)), address(sut));
    }
}
