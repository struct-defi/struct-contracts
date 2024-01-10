pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@mocks/MockERC20.sol";
import "@interfaces/IGAC.sol";
import "@core/common/StructPriceOracle.sol";
import "@core/libraries/types/DataTypes.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../../common/yield-sources/GMXYieldSourceHarness.sol";

import "../../common/BaseTestSetup.sol";

contract GMXYieldSource_UnitTest is BaseTestSetup {
    /// System under test
    GMXYieldSourceHarness internal sut;

    IERC20Metadata internal constant wavax = IERC20Metadata(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20Metadata internal constant usdc = IERC20Metadata(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);

    function onSetup() public virtual override {
        setLabels();

        sut = new GMXYieldSourceHarness(mockFactory, address(gac));
    }

    function setLabels() internal {
        vm.label(mockFactory, "MockFactory");
        vm.label(address(wavax), "wAVAX");
        vm.label(address(usdc), "USDC");
        vm.label(address(sut), "GMXYieldSource");
    }

    function testSetFEYGMXProductInfo_RevertInvalidAccess() public {
        console.log("GMX_YS_SFGPI_1");
        console.log("Reverts when called with valid data from non-factory contract");
        DataTypes.FEYGMXProductInfo memory _feyGmxProductInfo = DataTypes.FEYGMXProductInfo({
            tokenA: address(wavax),
            tokenADecimals: 18,
            tokenB: address(usdc),
            tokenBDecimals: 6,
            fsGLPReceived: 0,
            shares: 0,
            sameToken: false
        });
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.setFEYGMXProductInfo(address(mockProduct), _feyGmxProductInfo);
    }

    function testSetFEYGMXProductInfo_Success() public {
        console.log("GMX_YS_SFGPI_2");
        console.log("Succeeds when called with valid data from factory contract");
        DataTypes.FEYGMXProductInfo memory _feyGmxProductInfo = DataTypes.FEYGMXProductInfo({
            tokenA: address(wavax),
            tokenADecimals: 18,
            tokenB: address(usdc),
            tokenBDecimals: 6,
            fsGLPReceived: 0,
            shares: 0,
            sameToken: false
        });
        vm.prank(mockFactory);
        sut.setFEYGMXProductInfo(address(mockProduct), _feyGmxProductInfo);
        DataTypes.FEYGMXProductInfo memory _productInfo = sut.getFEYGMXProductInfo(address(mockProduct));
        assertEq(_productInfo.tokenA, _feyGmxProductInfo.tokenA);
        assertEq(_productInfo.tokenADecimals, _feyGmxProductInfo.tokenADecimals);
        assertEq(_productInfo.tokenB, _feyGmxProductInfo.tokenB);
        assertEq(_productInfo.tokenBDecimals, _feyGmxProductInfo.tokenBDecimals);
        assertEq(_productInfo.fsGLPReceived, _feyGmxProductInfo.fsGLPReceived);
        assertEq(_productInfo.shares, _feyGmxProductInfo.shares);
    }

    function testAddRewards_RevertACL() public {
        console.log("Should revert if called by an account without GOVERNANCE role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        address[] memory _products = new address[](2);
        _products[0] = address(0x1);
        _products[1] = address(0x2);
        sut.addRewards(_products, 10e18);
    }
}
