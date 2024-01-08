// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

/// External Imports
import {StructERC1155} from "./StructERC1155.sol";

/// Internal Imports
import {GACManaged} from "../common/GACManaged.sol";
import {IGAC} from "../../interfaces/IGAC.sol";
import {IFEYFactory} from "../../interfaces/IFEYFactory.sol";

/**
 * @title StructSP Token
 * @notice A simple implementation of ERC1155 token using OpenZeppelin libraries
 * @dev This contract implements the StructSP Token, which is an ERC1155 token using OpenZeppelin libraries.
 * It also makes use of GACManaged for access control.
 * @author Struct Finance
 */
contract StructSPToken is StructERC1155, GACManaged {
    // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
    string private _uri;

    IFEYFactory private feyProductFactory;

    event FEYProductFactoryUpdated(address indexed newFactory);

    constructor(IGAC _globalAccessControl, IFEYFactory _feyProductFactory) {
        __GACManaged_init(_globalAccessControl);
        feyProductFactory = _feyProductFactory;
    }

    /**
     * @dev Transfers tokens from one address to another
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param id The ID of the token to transfer
     * @param amount The amount of the token to transfer
     * @param data Additional data with no specified format
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data)
        public
        virtual
        override
        gacPausable
    {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev Transfers multiple types of tokens from one address to another
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param ids The IDs of the tokens to transfer
     * @param amounts The amounts of the tokens to transfer
     * @param data Additional data with no specified format
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public virtual override gacPausable {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /**
     * @dev Mints tokens and assigns them to an address
     * @param to The address to assign the minted tokens to
     * @param id The ID of the token to mint
     * @param amount The amount of the token to mint
     * @param data Additional data with no specified format
     */
    function mint(address to, uint256 id, uint256 amount, bytes memory data)
        public
        virtual
        gacPausable
        onlyRole(PRODUCT)
    {
        _mint(to, id, amount, data);
    }

    /**
     * @dev Mints multiple types of tokens and assigns them to an address
     * @param to The address to assign the minted tokens to
     * @param ids The IDs of the tokens to mint
     * @param amounts The amounts of the tokens to mint
     * @param data Additional data with no specified format
     */
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        virtual
        gacPausable
        onlyRole(PRODUCT)
    {
        _batchMint(to, ids, amounts, data);
    }

    /**
     * @notice Burn a certain amount of a specific token ID.
     * @param from The address of the token owner.
     * @param id The ID of the token to burn.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 id, uint256 amount) public virtual onlyRole(PRODUCT) gacPausable {
        require(_msgSender() == from || isApprovedForAll[from][_msgSender()], "NOT_AUTHORIZED");
        _burn(from, id, amount);
    }

    /**
     * @notice Burn multiple amounts of different token IDs.
     * @param from The address of the token owner.
     * @param ids The IDs of the tokens to burn.
     * @param amounts The amounts of tokens to burn.
     */
    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts)
        public
        virtual
        onlyRole(PRODUCT)
        gacPausable
    {
        require(_msgSender() == from || isApprovedForAll[from][_msgSender()], "NOT_AUTHORIZED");
        _batchBurn(from, ids, amounts);
    }

    /**
     * @notice Hook that restricts the token transfers if the state of the associated product is not `INVESTED`.
     * @dev Also restricts the minting once the deposits are closed for the associated product.
     * @param operator The address performing the operation.
     * @param from The address from which the tokens are transferred.
     * @param to The address to which the tokens are transferred.
     * @param ids The IDs of the tokens being transferred.
     * @param amounts The amounts of tokens being transferred.
     * @param data Additional data with no specified format.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override gacPausable {
        /// if mint, check if minting is enabled for the product
        if (from == address(0)) {
            uint256 idsLength = ids.length;
            for (uint256 i = 0; i < idsLength;) {
                require(feyProductFactory.isMintActive(ids[i]), "MINT_DISABLED");

                unchecked {
                    i++;
                }
            }
            /// for transfers (excluding `burn()`), check if transfer is enabled for the product
        } else if (to != address(0)) {
            uint256 idsLength = ids.length;
            for (uint256 i = 0; i < idsLength;) {
                require(feyProductFactory.isTransferEnabled(ids[i], from), "TRANSFER_DISABLED");
                unchecked {
                    i++;
                }
            }
        }
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
     * @notice Set the base token URI for all token IDs.
     * @param newuri The new URI to set.
     */
    function setURI(string memory newuri) external onlyRole(GOVERNANCE) {
        _setURI(newuri);
    }

    /**
     * @notice Set the address of the FeyProductFactory contract.
     * @param _feyProductFactory The address of the FeyProductFactory contract.
     */
    function setFeyProductFactory(IFEYFactory _feyProductFactory) external onlyRole(GOVERNANCE) {
        feyProductFactory = _feyProductFactory;
        emit FEYProductFactoryUpdated(address(_feyProductFactory));
    }

    /**
     * @notice Internal function to set the base token URI for all token IDs.
     * @param newuri The new URI to set.
     */
    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }

    /**
     * @notice Returns the base token URI for all token IDs.
     */
    function uri(uint256) public view virtual override returns (string memory) {
        return _uri;
    }

    /**
     * @dev Override function required by ERC-165 to check if a contract implements a given interface.
     * @param interfaceId The ID of the interface to check.
     * @return A boolean indicating whether the contract implements the interface with the given ID.
     */
    function supportsInterface(bytes4 interfaceId) public pure override(StructERC1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
