// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@interfaces/IFEYProduct.sol";
import "@interfaces/IGAC.sol";
import "@external/IWETH9.sol";
import "@core/libraries/types/DataTypes.sol";

import "@mocks/ERC1155ReceiverMock.sol";

/**
 * @title Product User contract
 * @notice User contract to interact with FEY Contract.
 *
 */
contract FEYProductUser is ERC1155Holder {
    IFEYProduct public feyProduct;

    uint256 public avaxBalanceBefore = 0;
    uint256 public avaxBalanceAfter = 0;
    mapping(uint256 => uint256) public spTokenBalanceBefore;
    mapping(uint256 => uint256) public spTokenBalanceAfter;
    mapping(address => uint256) public trancheTokenBalanceBefore;
    mapping(address => uint256) public trancheTokenBalanceAfter;

    constructor(address _feyProduct) {
        feyProduct = IFEYProduct(_feyProduct);
    }

    function recordTrancheTokenBalance(IERC20Metadata _token, bool _isBefore) public {
        if (_isBefore) {
            trancheTokenBalanceBefore[address(_token)] = _token.balanceOf(address(this));
        } else {
            trancheTokenBalanceAfter[address(_token)] = _token.balanceOf(address(this));
        }
    }

    function recordSpTokenBalance(bool _isBefore, DataTypes.Tranche _tranche, uint256 _amount) public {
        if (_isBefore) {
            spTokenBalanceBefore[uint256(_tranche)] = _amount;
        } else {
            spTokenBalanceAfter[uint256(_tranche)] = _amount;
        }
    }

    function recordAvaxBalance(bool _isBefore) public {
        if (_isBefore) {
            avaxBalanceBefore = address(this).balance;
        } else {
            avaxBalanceAfter = address(this).balance;
        }
    }

    function balanceOf() external view returns (uint256) {
        return address(feyProduct).balance;
    }

    function depositToSenior(uint256 _amount) external {
        feyProduct.deposit(DataTypes.Tranche.Senior, _amount);
    }

    function depositAvaxToSenior(uint256 _amount, uint256 _value) external {
        feyProduct.deposit{value: _value}(DataTypes.Tranche.Senior, _amount);
    }

    function depositForAvaxToSenior(uint256 _amount, uint256 _value, address _onBehalfOf) external {
        feyProduct.depositFor{value: _value}(DataTypes.Tranche.Senior, _amount, _onBehalfOf);
    }

    function depositForAvaxToJunior(uint256 _amount, uint256 _value, address _onBehalfOf) external {
        feyProduct.depositFor{value: _value}(DataTypes.Tranche.Junior, _amount, _onBehalfOf);
    }

    function depositAvaxToJunior(uint256 _amount, uint256 _value) external {
        feyProduct.deposit{value: _value}(DataTypes.Tranche.Junior, _amount);
    }

    function depositToJunior(uint256 _amount) external {
        feyProduct.deposit(DataTypes.Tranche.Junior, _amount);
    }

    function depositToSeniorFor(uint256 _amount, address _onBehalfOf) external {
        feyProduct.depositFor(DataTypes.Tranche.Senior, _amount, _onBehalfOf);
    }

    function depositToJuniorFor(uint256 _amount, address _onBehalfOf) external {
        feyProduct.depositFor(DataTypes.Tranche.Junior, _amount, _onBehalfOf);
    }

    function invest() external {
        feyProduct.invest();
    }

    function removeFundsFromLP() external {
        feyProduct.removeFundsFromLP();
    }

    function claimExcess(DataTypes.Tranche _tranche) external {
        feyProduct.claimExcess(_tranche);
    }

    function emergencyWithdraw() external {}

    function withdraw(DataTypes.Tranche _tranche) external {
        feyProduct.withdraw(_tranche);
    }

    function emergencyRemoveLiquidity(uint256 _amountA, uint256 _amountB) external {}

    function increaseAllowance(address _token, uint256 _amount) external {
        IERC20Metadata(_token).approve(address(feyProduct), _amount);
    }

    function setApprovalForAll(IERC1155 _token, address _operator) external {
        IERC1155(_token).setApprovalForAll(_operator, true);
    }

    function localPause() external {
        IGAC(address(feyProduct)).pause();
    }

    function localUnpause() external {
        IGAC(address(feyProduct)).unpause();
    }

    function globalPause() external {
        (, bytes memory data) = address(feyProduct).call(abi.encodeWithSignature("gac()"));
        address gacAddress = abi.decode(data, (address));
        IGAC(gacAddress).pause();
    }

    function globalUnpause() external {
        (, bytes memory data) = address(feyProduct).call(abi.encodeWithSignature("gac()"));
        address gacAddress = abi.decode(data, (address));
        IGAC(gacAddress).unpause();
    }

    function getInvestedAndExcess(DataTypes.Tranche _tranche) external view returns (uint256, uint256) {
        return feyProduct.getUserInvestmentAndExcess(_tranche, address(this));
    }

    function getTrancheInfo(DataTypes.Tranche _tranche) external view returns (DataTypes.TrancheInfo memory) {
        return feyProduct.getTrancheInfo(_tranche);
    }

    function trancheConfig(DataTypes.Tranche _tranche) external view returns (DataTypes.TrancheConfig memory) {
        return feyProduct.getTrancheConfig(_tranche);
    }

    function getInvestorDetails(DataTypes.Tranche _tranche) external view returns (DataTypes.Investor memory) {
        return feyProduct.getInvestorDetails(_tranche, address(this));
    }

    receive() external payable {
        // For receiving ether
    }
}
