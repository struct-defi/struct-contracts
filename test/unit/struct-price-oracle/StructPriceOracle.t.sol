// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "forge-std/src/Test.sol";
import "@core/common/StructPriceOracle.sol";
import "../../common/price-oracle/PriceOracleUser.sol";

contract StructPriceOracleTest is Test {
    StructPriceOracle internal sut;
    address[] internal assets;
    AggregatorV3Interface[] internal sources;

    PriceOracleUser internal user1;

    uint256 internal assetPrice = 1e8;
    address internal assetAddress = vm.addr(0xa);
    AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x0A77230d17318075983913bC2145DB16C7366156);

    event AssetSourceUpdated(address indexed asset, address indexed source);

    function setUp() public virtual {
        initPriceOracle();
        setContractsLabels();
        createUsers(address(sut));
    }

    function initPriceOracle() public {
        assets.push(assetAddress);
        sources.push(priceFeed);
        sut = new StructPriceOracle(assets, sources);
    }

    function setContractsLabels() internal {
        vm.label(address(user1), "User 1");

        vm.label(address(sut), "Struct Price Oracle");
        vm.label(address(this), "Test Contract");
    }

    function createUsers(address _priceOracle) internal {
        user1 = new PriceOracleUser(_priceOracle);
    }

    function mockAggregatorV3(address _priceFeed, uint80 _roundId, uint256 _assetPrice) internal {
        uint80 roundId = _roundId;
        uint256 startedAt = 0;
        uint256 updatedAt = 0;
        uint80 answeredInRound = 0;
        uint256 tokenDecimals = 18;

        vm.mockCall(
            address(_priceFeed),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, _assetPrice, startedAt, updatedAt, answeredInRound)
        );

        vm.mockCall(
            address(_priceFeed),
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(tokenDecimals)
        );
    }

    function testConstructor_PersistAssetSources() public {
        console.log("should persist asset sources when initialized");
        console.log("ID: SPO_cons_1");
        assets.push(assetAddress);
        sources.push(priceFeed);
        vm.expectEmit(true, true, true, true);
        emit AssetSourceUpdated(assetAddress, address(priceFeed));
        sut = new StructPriceOracle(assets, sources);
        address assetSource = sut.getSourceOfAsset(assetAddress);
        assertEq(assetSource, address(priceFeed));
    }

    function testSetAssetSources_PersistAssetSources() public {
        console.log("should persist asset sources when called by owner");
        console.log("ID: SPO_SASs_1");
        assets.push(assetAddress);
        sources.push(priceFeed);
        vm.expectEmit(true, true, true, true);
        emit AssetSourceUpdated(assetAddress, address(priceFeed));
        sut.setAssetSources(assets, sources);
        address assetSource = sut.getSourceOfAsset(assetAddress);
        assertEq(assetSource, address(priceFeed));
    }

    function testSetAssetSources_RevertInconsistentParamsLength() public {
        console.log("should revert with error INCONSISTENT_PARAMS_LENGTH if assets.length != sources.length");
        console.log("ID: SPO_SASs_2");
        // push two asset addresses
        assets.push(assetAddress);
        assets.push(assetAddress);
        sources.push(priceFeed);
        vm.expectRevert(abi.encodePacked("INCONSISTENT_PARAMS_LENGTH"));
        sut.setAssetSources(assets, sources);
    }

    function testSetAssetSources_RevertCallerNotOwner() public {
        console.log("should revert with error 'Ownable: caller is not the owner' when called by non-owner");
        console.log("ID: SPO_SASs_3");
        assets.push(assetAddress);
        sources.push(priceFeed);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        user1.setAssetSources(assets, sources);
    }

    function testGetAssetPrice_ReturnAssetPrice() public {
        console.log("should return asset price");
        console.log("ID: SPO_GAP_1");
        assets.push(assetAddress);
        sources.push(priceFeed);
        uint80 correctRoundId = 0;
        mockAggregatorV3(address(priceFeed), correctRoundId, assetPrice);
        uint256 _assetPrice = sut.getAssetPrice(assetAddress);
        assertEq(_assetPrice, assetPrice);
    }

    function testGetAssetPrice_RevertInvalidRoundId() public {
        console.log("should revert with error OUTDATED if invalid roundId");
        console.log("ID: SPO_GAP_2");
        assets.push(assetAddress);
        sources.push(priceFeed);
        uint80 incorrectRoundId = 1;
        mockAggregatorV3(address(priceFeed), incorrectRoundId, assetPrice);
        vm.expectRevert(abi.encodePacked("OUTDATED"));
        sut.getAssetPrice(assetAddress);
    }

    function testGetAssetPrice_RevertInvalidPrice() public {
        console.log("should revert with error INVALID_PRICE if price returned is zero");
        console.log("ID: SPO_GAP_2");
        assets.push(assetAddress);
        sources.push(priceFeed);
        uint80 correctRoundId = 0;
        uint256 assetPriceZero = 0;
        mockAggregatorV3(address(priceFeed), correctRoundId, assetPriceZero);
        vm.expectRevert(abi.encodePacked("INVALID_PRICE"));
        sut.getAssetPrice(assetAddress);
    }

    function testGetAssetsPrices_ReturnAssetPrices() public {
        console.log("should return all asset prices");
        console.log("ID: SPO_GAPs_1");
        assets.push(assetAddress);
        sources.push(priceFeed);
        uint80 correctRoundId = 0;
        mockAggregatorV3(address(priceFeed), correctRoundId, assetPrice);
        uint256[] memory _prices = sut.getAssetsPrices(assets);
        assertEq(_prices[0], assetPrice);
    }

    function testGetAssetsPrices_RevertInvalidRoundId() public {
        console.log("should revert with error OUTDATED if invalid roundId on any asset");
        console.log("ID: SPO_GAPs_2");
        assets.push(assetAddress);
        sources.push(priceFeed);
        uint80 incorrectRoundId = 1;
        mockAggregatorV3(address(priceFeed), incorrectRoundId, assetPrice);
        vm.expectRevert(abi.encodePacked("OUTDATED"));
        sut.getAssetsPrices(assets);
    }

    function testGetAssetsPrices_RevertInvalidPrice() public {
        console.log("should revert with error INVALID_PRICE if any price returned is zero");
        console.log("ID: SPO_GAPs_3");
        assets.push(assetAddress);
        sources.push(priceFeed);
        uint80 correctRoundId = 0;
        uint256 assetPriceZero = 0;
        mockAggregatorV3(address(priceFeed), correctRoundId, assetPriceZero);
        vm.expectRevert(abi.encodePacked("INVALID_PRICE"));
        sut.getAssetsPrices(assets);
    }

    function testGetSourceOfAsset_ReturnAssetSource() public {
        console.log("should return source of asset");
        console.log("ID: SPO_GSOA_1");
        address _assetSource = sut.getSourceOfAsset(assetAddress);
        assertEq(_assetSource, address(priceFeed));
    }
}
