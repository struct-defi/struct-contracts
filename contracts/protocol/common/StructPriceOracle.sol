// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// External Imports
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// Internal Imports
import "../../interfaces/IStructPriceOracle.sol";

/**
 * @title Struct Price oracle for the tranche tokens
 * @notice This contract uses Chainlink's price feed to fetch the latest price of the given assets
 * @author Struct Finance
 */
contract StructPriceOracle is IStructPriceOracle, Ownable {
    /// @dev Asset -> ChainlinkSourceAddress mapping
    mapping(address => AggregatorV3Interface) private assetsSources;

    event AssetSourceUpdated(address indexed asset, address indexed source);

    /*////////////////////////////////////////////////////////////*/
    /*                     CONSTRUCTOR                            */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @param assets The addresses of the assets
     * @param sources The address of the Chainlink aggregator of each asset
     */
    constructor(address[] memory assets, AggregatorV3Interface[] memory sources) {
        _setAssetsSources(assets, sources);
    }

    /*////////////////////////////////////////////////////////////*/
    /*                           SETTERS                          */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to set or replace sources for the assets
     * @param assets The addresses of the assets
     * @param sources The address of the source of each asset
     */
    function setAssetSources(address[] calldata assets, AggregatorV3Interface[] calldata sources) external onlyOwner {
        _setAssetsSources(assets, sources);
    }

    function _setAssetsSources(address[] memory assets, AggregatorV3Interface[] memory sources) internal {
        require(assets.length == sources.length, "INCONSISTENT_PARAMS_LENGTH");
        for (uint256 i = 0; i < assets.length; i++) {
            assetsSources[assets[i]] = sources[i];
            emit AssetSourceUpdated(assets[i], address(sources[i]));
        }
    }

    /*////////////////////////////////////////////////////////////*/
    /*                           GETTERS                          */
    /*////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets an asset price by address
     * @param asset The asset address
     * @return The asset price in 18 decimals
     */
    function getAssetPrice(address asset) public view override returns (uint256) {
        (uint80 roundId, int256 price,,, uint80 answeredInRound) = assetsSources[asset].latestRoundData();

        require(roundId == answeredInRound, "OUTDATED");
        require(price > 0, "INVALID_PRICE");
        return (uint256(price) * 10 ** 18) / 10 ** assetsSources[asset].decimals();
    }

    /**
     * @notice Gets a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return prices The list of asset prices in 18 decimals
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /**
     * @notice Gets the address of the source for an asset address
     * @param asset The address of the asset
     * @return address The address of the source
     */
    function getSourceOfAsset(address asset) external view returns (address) {
        return address(assetsSources[asset]);
    }
}
