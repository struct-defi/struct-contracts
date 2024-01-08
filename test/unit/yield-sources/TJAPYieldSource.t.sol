pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@core/yield-sources/AutoPoolYieldSource.sol";
import "@core/libraries/helpers/Errors.sol";
import "@external/traderjoe/IAPTFarm.sol";
import "@external/traderjoe/IAutoPoolVault.sol";
import "@interfaces/IAutoPoolYieldSource.sol";
import "@mocks/MockERC20.sol";
import "@mocks/MockRewarder.sol";

import "../../common/BaseTestSetup.sol";

contract TJAPYieldSource_UnitTest is BaseTestSetup {
    /// System under test
    AutoPoolYieldSource internal sut;

    IERC20Metadata internal wavax;
    IERC20Metadata internal usdc;
    IAPTFarm public constant APT_FARM = IAPTFarm(0x57FF9d1a7cf23fD1A9fd9DC07823F950a22a718C);

    address autoPoolVault = makeAddr("autoPoolVault");

    function onSetup() public virtual override {
        wavax = IERC20Metadata(address(new MockERC20("MockWAVAX", "mWAVAX",18)));
        usdc = IERC20Metadata(address(new MockERC20("MockUSDC", "mUSDC",6)));

        vm.mockCall(
            address(autoPoolVault),
            abi.encodeWithSelector(IAutoPoolVault.getTokenX.selector),
            abi.encode(address(wavax))
        );
        vm.mockCall(
            address(autoPoolVault), abi.encodeWithSelector(IAutoPoolVault.getTokenY.selector), abi.encode(address(usdc))
        );

        vm.mockCall(address(autoPoolVault), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(12));

        vm.mockCall(address(APT_FARM), abi.encodeWithSelector(IAPTFarm.vaultFarmId.selector), abi.encode(0));

        IAPTFarm.FarmInfo memory _farmInfo = IAPTFarm.FarmInfo(
            IERC20(0x32833a12ed3Fd5120429FB01564c98ce3C60FC1d),
            13602996785183687529309514525636914715470,
            1691502560,
            12400793000000000,
            IRewarder(0x0000000000000000000000000000000000000000)
        );
        vm.mockCall(address(APT_FARM), abi.encodeWithSelector(IAPTFarm.farmInfo.selector), abi.encode(_farmInfo));
        vm.mockCall(
            address(APT_FARM),
            abi.encodeWithSelector(IAPTFarm.hasFarm.selector, address(autoPoolVault)),
            abi.encode(true)
        );
        /// Deploy Yield Source
        sut =
        new AutoPoolYieldSource(IAutoPoolVault(autoPoolVault), IGAC(address(gac)), IStructPriceOracle(makeAddr('oracle')));
    }

    function testRescueTokensTJAP_ShouldTransferERC20Tokens(address _recipient, uint256 _amount) public {
        vm.assume(_recipient != address(0) && _recipient != address(sut));
        vm.assume(_amount > 0);

        deal(address(wavax), address(sut), _amount);

        uint256 _balanceBeforeSUT = wavax.balanceOf(address(sut));
        uint256 _balanceBeforeRecipient = wavax.balanceOf(address(_recipient));

        vm.prank(admin);
        sut.rescueTokens(IERC20Metadata(address(wavax)), _amount, _recipient, false);

        uint256 _balanceAfterSUT = wavax.balanceOf(address(sut));
        uint256 _balanceAfterRecipient = wavax.balanceOf(address(_recipient));

        assertEq(_balanceAfterSUT, _balanceBeforeSUT - _amount, "contract: balanceAfter == balanceBefore - amount");
        assertEq(
            _balanceAfterRecipient, _balanceBeforeRecipient + _amount, "user: balanceAfter == balanceBefore + amount"
        );
    }

    function testRescueTokensTJAP_ShouldTransferNativeTokens(uint256 _amount) public {
        MockRewarder receiver = new MockRewarder(address(wavax),true);
        address _recipient = address(receiver);

        vm.assume(_amount > 0);

        deal(address(sut), _amount);

        uint256 _balanceBeforeSUT = address(sut).balance;
        uint256 _balanceBeforeRecipient = _recipient.balance;

        vm.prank(admin);
        sut.rescueTokens(IERC20Metadata(address(0)), _amount, _recipient, true);

        uint256 _balanceAfterSUT = address(sut).balance;
        uint256 _balanceAfterRecipient = _recipient.balance;

        assertEq(_balanceAfterSUT, _balanceBeforeSUT - _amount, "contract: balanceAfter == balanceBefore - amount");
        assertEq(
            _balanceAfterRecipient, _balanceBeforeRecipient + _amount, "user: balanceAfter == balanceBefore + amount"
        );
    }

    function testRescueTokensTJAP_ShouldRevert_IfInvalidReceiver() public {
        console.log("should revert with `ZeroAddress()` error if zero address is passed as recipient");
        uint256 _amount = 100;
        address _recipient = address(0);
        bool _isNative = false;

        deal(address(wavax), address(sut), _amount);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.ZeroAddress.selector));
        sut.rescueTokens(IERC20Metadata(address(wavax)), 0, _recipient, _isNative);
        vm.stopPrank();
    }

    function testRescueTokensTJAP_OnlyGovernance(uint256 _amount, address _recipient, bool _isNative) public {
        console.log("should be called only by GOVERNANCE");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.rescueTokens(IERC20Metadata(address(wavax)), _amount, _recipient, _isNative);
    }

    function testSetSwapPath_Success() public {
        console.log("should set all swap path types successfully");
        address nativeToTokenASwapPath0 = sut.nativeToTokenASwapPath(0);
        address nativeToTokenBSwapPath0 = sut.nativeToTokenBSwapPath(0);
        address reward2ToNativeSwapPath0 = sut.reward2ToNativeSwapPath(0);
        address tokenAToTokenBSwapPath0 = sut.tokenAToTokenBSwapPath(0);
        address tokenBToTokenASwapPath0 = sut.tokenBToTokenASwapPath(0);

        vm.startPrank(address(admin));

        address[] memory _newPath1 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.NativeToTokenA, _newPath1);
        assertNotEq(nativeToTokenASwapPath0, sut.nativeToTokenASwapPath(0), "NativeToTokenA path should be updated");

        address[] memory _newPath2 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.NativeToTokenB, _newPath2);
        assertNotEq(nativeToTokenBSwapPath0, sut.nativeToTokenBSwapPath(0), "NativeToTokenB path should be updated");

        address[] memory _newPath3 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.Reward2ToNative, _newPath3);
        assertNotEq(reward2ToNativeSwapPath0, sut.reward2ToNativeSwapPath(0), "Reward2ToNative path should be updated");

        address[] memory _newPath4 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.TokenAToTokenB, _newPath4);
        assertNotEq(tokenAToTokenBSwapPath0, sut.tokenAToTokenBSwapPath(0), "TokenAToTokenB path should be updated");

        address[] memory _newPath5 = generateNewPath();
        sut.setSwapPath(DataTypes.SwapPathType.TokenBToTokenA, _newPath5);
        assertNotEq(tokenBToTokenASwapPath0, sut.tokenBToTokenASwapPath(0), "TokenBToTokenA path should be updated");
        vm.stopPrank();
    }

    function testSetSwapPath_Revert_InvalidSwapPathType() public {
        console.log("should revert if the swap path type does not exist");
        address[] memory _newPath = generateNewPath();
        vm.startPrank(address(admin));
        vm.expectRevert(abi.encodeWithSelector(IAutoPoolYieldSource.InvalidSwapPathType.selector));
        sut.setSwapPath(DataTypes.SwapPathType.SeniorToNative, _newPath);
        vm.stopPrank();
    }

    function testSetSlippage_Success() public {
        console.log("should update the slippage");
        uint256 _newSlippage = 5e8;
        vm.startPrank(address(admin));
        sut.setSlippage(_newSlippage);
        vm.stopPrank();

        assertEq(sut.slippage(), _newSlippage);
    }

    function testSetSlippage_Revert_ACL() public {
        console.log("should not update the slippage if the caller is not GOVERNOR");
        uint256 _newSlippage = 5e8;
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));

        sut.setSlippage(_newSlippage);

        assertNotEq(sut.slippage(), _newSlippage);
    }

    function testSetSwapPath_Revert_InvalidAccess() public {
        console.log("should revert if the caller does not have governance role");
        address[] memory _newPath = generateNewPath();
        vm.startPrank(address(user1));
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        sut.setSwapPath(DataTypes.SwapPathType.TokenAToTokenB, _newPath);
        vm.stopPrank();
    }

    function generateNewPath() internal returns (address[] memory _newPath) {
        _newPath = new address[](2);
        _newPath[0] = getNextAddress();
        _newPath[1] = getNextAddress();
        return _newPath;
    }
}
