// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import {console} from "forge-std/src/console.sol";
import {BaseTestSetup} from "../../common/BaseTestSetup.sol";
import {StructSPToken} from "@core/tokenization/StructSPToken.sol";
import {IFEYFactory} from "@interfaces/IFEYFactory.sol";
import {IGAC} from "@interfaces/IGAC.sol";

contract StructSpToken_UnitTest is BaseTestSetup {
    StructSPToken public sut;
    uint256 public id = 1;
    uint256 public amount = 1e18;
    uint256[] public ids;
    uint256[] public amounts;

    function onSetup() public override {
        sut = new StructSPToken(IGAC(address(gac)), IFEYFactory(mockFactory));
        vm.mockCall(mockFactory, abi.encodeWithSelector(IFEYFactory.isMintActive.selector), abi.encode(true));
    }

    function testMint_Success() public {
        console.log("ID: Sp_Mi_1");
        vm.prank(mockProduct);
        sut.mint(mockProduct, id, amount, "0x0");
        uint256 _balance = sut.balanceOf(mockProduct, id);
        assertEq(_balance, amount, "account's SP token balance should be equal to amount minted");
        uint256 _totalSupply = sut.totalSupply(id);
        assertEq(_totalSupply, amount, "total supply should be equal to amount minted");
    }

    function testMintBatch_Success() public {
        console.log("ID: Sp_BaMi_1");
        ids.push(id);
        amounts.push(amount);
        vm.prank(mockProduct);
        sut.mintBatch(mockProduct, ids, amounts, "0x0");
        uint256 _balance = sut.balanceOf(mockProduct, id);
        assertEq(_balance, amount, "account's SP token balance should be equal to amount minted");
        uint256 _totalSupply = sut.totalSupply(id);
        assertEq(_totalSupply, amount, "total supply should be equal to amount minted");
    }

    function testBurn_Success() public {
        console.log("ID: Sp_Bu_1");
        vm.prank(mockProduct);
        sut.mint(mockProduct, id, amount, "0x0");

        vm.prank(mockProduct);
        sut.burn(mockProduct, id, amount);
        uint256 _balance = sut.balanceOf(mockProduct, id);
        assertEq(_balance, 0, "account's SP token balance should be 0");
        uint256 _totalSupply = sut.totalSupply(id);
        assertEq(_totalSupply, 0, "total supply should be 0");
    }

    function testBatchBurn_Success() public {
        console.log("ID: Sp_BaBu_1");
        ids.push(id);
        amounts.push(amount);
        vm.prank(mockProduct);
        sut.mintBatch(mockProduct, ids, amounts, "0x0");

        vm.prank(mockProduct);
        sut.burnBatch(mockProduct, ids, amounts);
        uint256 _balance = sut.balanceOf(mockProduct, id);
        assertEq(_balance, 0, "account's SP token balance should be 0");
        uint256 _totalSupply = sut.totalSupply(id);
        assertEq(_totalSupply, 0, "total supply should be 0");
    }
}
