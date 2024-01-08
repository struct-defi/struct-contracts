pragma solidity 0.8.11;

import "@core/libraries/types/DataTypes.sol";
import "@core/libraries/helpers/Errors.sol";
import "../../../common/fey-products/autopool/FEYProductBaseTestSetup.sol";

contract FEYAutoPoolProductSetSwapPathTest is FEYProductBaseTestSetup {
    error InvalidSwapPathType();

    function setUp() public virtual override {
        super.setUp();
    }

    function onSetup() public virtual override {
        depositInvestTestsFixture(seniorTrancheIsWAVAX);
    }

    function testSetSwapPath_Success() public {
        console.log("should set all swap path types successfully");
        address seniorTokenToNativeSwapPath0 = sut.seniorTokenToNativeSwapPath(0);
        address juniorTokenToNativeSwapPath0 = sut.juniorTokenToNativeSwapPath(0);

        vm.startPrank(address(admin));

        address[] memory _newPath1 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.SeniorToNative, _newPath1);
        assertNotEq(
            seniorTokenToNativeSwapPath0, sut.seniorTokenToNativeSwapPath(0), "SeniorToNative path should be updated"
        );

        address[] memory _newPath2 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.JuniorToNative, _newPath2);
        assertNotEq(
            juniorTokenToNativeSwapPath0, sut.juniorTokenToNativeSwapPath(0), "JuniorToNative path should be updated"
        );
        vm.stopPrank();
    }

    function testSetSwapPath_Revert_InvalidAccess() public {
        console.log("should revert if the caller does not have governance role");
        address[] memory _newPath = generateNewPath();
        vm.startPrank(address(user1));
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.setSwapPath(DataTypes.SwapPathType.SeniorToNative, _newPath);
        vm.stopPrank();
    }

    function generateNewPath() internal returns (address[] memory _newPath) {
        _newPath = new address[](2);
        _newPath[0] = getNextAddress();
        _newPath[1] = getNextAddress();
        return _newPath;
    }
}
