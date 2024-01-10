// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/// External imports
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface ISPToken is IERC1155 {
    /// @notice mints the given erc1155 token id to the given address
    /// @param to the recipient of the token
    /// @param id the id of the ERC1155 token to be minted
    /// @param amount amount of tokens to be minted
    /// @param data optional field to execute other methods after tokens are minted
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;

    /// @notice burns the erc1155 tokens
    /// @param from the address of the token owner
    /// @param id the id of the token to be burnt
    /// @param amount the amount of tokens to be burnt
    function burn(address from, uint256 id, uint256 amount) external;

    /// @notice gets the total circulating supply of the given token id
    /// @param id the id of the token
    /// @return the total circulating supply of the token
    function totalSupply(uint256 id) external view returns (uint256);
}
