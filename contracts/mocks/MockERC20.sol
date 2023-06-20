// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20, Ownable {
    uint8 public _decimals;

    constructor(string memory _tokenName, string memory _tokenSymbol, uint8 decimals_)
        payable
        ERC20(_tokenName, _tokenSymbol)
    {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
