// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Test, console} from "forge-std/src/Test.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {DistributionManager} from "@core/misc/DistributionManager.sol";
import {GlobalAccessControl} from "@core/common/GlobalAccessControl.sol";
import {Errors} from "@core/libraries/helpers/Errors.sol";

import {IDistributionManager} from "@interfaces/IDistributionManager.sol";
import {IGAC} from "@interfaces/IGAC.sol";

import {DistributionManagerUser} from "../../common/distribution-manager/DistributionManagerUser.sol";
import {RewardsRecipient} from "../../common/distribution-manager/RewardsRecipient.sol";

contract DistributionManager_UnitTest is Test {
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    // contracts
    GlobalAccessControl internal gac;
    RewardsRecipient internal destinationContract;
    DistributionManager internal sut;
    DistributionManagerUser internal user1;
    address internal mockProduct;

    // test values
    uint256 internal queuedNative = 10e18;
    address internal destination = vm.addr(0xa);
    uint256 internal allocatedTotalPoints = 1e3;
    uint256 internal allocationPoints = 1e3;
    uint256 internal allocationFee = 1e3;
    uint256 internal rewardsPerSec = 1;
    IDistributionManager.RecipientData[] internal recipients;
    MockERC20 internal structToken = new MockERC20("STRUCT", "STRUCT", 18);
    MockERC20 internal nativeToken = new MockERC20("wAVAX", "Wrapped AVAX", 18);
    IDistributionManager.RecipientData internal recipient1 =
        IDistributionManager.RecipientData(destination, allocationPoints, allocationFee);

    // events
    event AddRecipient(uint256 _index, address indexed _destination, uint256 _allocationPoints, uint256 _allocationFee);

    event EditRecipient(
        uint256 _index, address indexed _destination, uint256 _allocationPoints, uint256 _allocationFee
    );

    event DistributionFrequencyUpdate(uint256 _distributionFrequencyMin);

    event DistributionDurationUpdate(uint256 _distributionDuration);

    function setUp() public virtual {
        initDistrManager();
        setContractsLabels();
        grantRoles();
        createUsers(address(sut));
    }

    function initDistrManager() public {
        gac = new GlobalAccessControl(address(this));

        // change destination to RewardsRecipient to use notifyRewardAmount method
        destinationContract = new RewardsRecipient();
        address _destination = address(destinationContract);
        recipient1.destination = _destination;

        recipients.push(recipient1);
        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            rewardsPerSec,
            IGAC(address(gac)),
            recipients
        );
        sut.initialize(IERC20Metadata(address(structToken)));
        destinationContract.setDistributionManager(address(sut));
    }

    function setContractsLabels() internal {
        vm.label(address(sut), "Distribution Manager");
        vm.label(address(this), "Test Contract");
        vm.label(address(structToken), "Struct Token");
        vm.label(address(nativeToken), "Native Token");
        vm.label(address(gac), "GAC");
        vm.label(address(user1), "User 1");
        vm.label(destination, "recipient1 destination");
    }

    function createUsers(address _distributionManager) internal {
        user1 = new DistributionManagerUser(_distributionManager);
    }

    function grantRoles() internal {
        gac.grantRole(DEFAULT_ADMIN_ROLE, address(sut));
        gac.grantRole(GOVERNANCE, address(sut));
        vm.startPrank(address(sut));
        gac.grantRole(FACTORY, address(sut));
        gac.grantRole(PRODUCT, address(mockProduct));
        vm.stopPrank();
    }

    function mockTokenBalances(uint256 _queuedNative) internal {
        vm.clearMockedCalls();

        vm.prank(mockProduct);
        sut.queueFees(_queuedNative);
        deal(address(nativeToken), address(sut), _queuedNative);
        deal(address(structToken), address(sut), _queuedNative);
    }

    function testConstructor_RevertInvalidAllocation() public {
        console.log("ID: DM_cons_1");
        console.log(
            "should revert with error VE_INVALID_ALLOCATION if recipient points and fee allocations are set to zero"
        );
        uint256 _allocationFee = 0;
        uint256 _allocationPoints = 0;
        IDistributionManager.RecipientData memory _recipient =
            IDistributionManager.RecipientData(destination, _allocationPoints, _allocationFee);
        delete recipients;
        recipients.push(_recipient);
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ALLOCATION));
        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            allocatedTotalPoints,
            IGAC(address(gac)),
            recipients
        );
    }

    function testConstructor_RevertInvalidZeroAddress() public {
        console.log("ID: DM_cons_3");
        console.log("should revert with error AE_ZERO_ADDRESS if recipient destination is set to zero address");
        address _destination = address(0);
        IDistributionManager.RecipientData memory _recipient =
            IDistributionManager.RecipientData(_destination, allocationPoints, allocationFee);
        delete recipients;
        recipients.push(_recipient);
        vm.expectRevert(abi.encodePacked(Errors.AE_ZERO_ADDRESS));
        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            allocatedTotalPoints,
            IGAC(address(gac)),
            recipients
        );
    }

    function testInit_RevertACL() public {
        console.log("ID: DM_init_1");
        console.log("should revert with error ACE_INVALID_ACCESS if called by non-governance role");
        vm.mockCall(
            address(structToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(allocatedTotalPoints)
        );

        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            allocatedTotalPoints,
            IGAC(address(gac)),
            recipients
        );
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.initialize(structToken);
    }

    function testInit_RevertInvalidZeroAddressStructToken() public {
        console.log("ID: DM_init_4");
        console.log("should revert with error AE_ZERO_ADDRESS if struct token is set to zero address");
        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            allocatedTotalPoints,
            IGAC(address(gac)),
            recipients
        );
        IERC20Metadata _structToken = IERC20Metadata(address(0));
        vm.expectRevert(abi.encodePacked(Errors.AE_ZERO_ADDRESS));
        sut.initialize(_structToken);
    }

    function testInit_RevertIsInitialized() public {
        console.log("ID: DM_init_10");
        console.log("should revert with error ACE_INITIALIZER if contract is already initialized");
        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            allocatedTotalPoints,
            IGAC(address(gac)),
            recipients
        );
        // init call 1
        sut.initialize(IERC20Metadata(address(structToken)));

        vm.expectRevert(abi.encodePacked(Errors.ACE_INITIALIZER));
        // init call 2
        sut.initialize(IERC20Metadata(address(structToken)));
    }

    function testInit_Success() public {
        console.log("ID: DM_init_11");
        console.log("should succeed if structToken interface is initialized with the structToken address");
        sut = new DistributionManager(
            IERC20Metadata(address(nativeToken)),
            allocatedTotalPoints,
            IGAC(address(gac)),
            recipients
        );
        sut.initialize(IERC20Metadata(address(structToken)));
        IERC20Metadata _structTokenActual = sut.structToken();
        assertEq(address(structToken), address(_structTokenActual), "struct token address");
    }

    function testAddDistrRecipient_Success() public {
        mockTokenBalances(queuedNative);

        address _destination2 = vm.addr(0xd);
        uint256 _allocationPoints2 = 2e8;
        uint256 _allocationFee2 = 2e8;
        uint256 _allocationPointsBefore = sut.totalAllocationPoints();
        uint256 _allocationFeeBefore = sut.totalAllocationFee();

        assertEq(sut.getRecipients().length, 1, "recipients length before adding");

        console.log("ID: DM_ADR_7");
        console.log("AddRecipient event is emitted when called by governance role");
        vm.expectEmit(true, true, true, true);
        emit AddRecipient(1, _destination2, _allocationPoints2, _allocationFee2);
        sut.addDistributionRecipient(_destination2, _allocationPoints2, _allocationFee2);

        console.log("ID: DM_ADR_1");
        console.log("recipients array increases by 1 when called by governance role");
        assertEq(sut.getRecipients().length, 2, "recipients length after adding");

        console.log("ID: DM_ADR_2");
        console.log("total allocation points is updated when called by governance role");
        uint256 _allocationPointsAfter = sut.totalAllocationPoints();
        assertEq(_allocationPointsBefore + _allocationPoints2, _allocationPointsAfter, "allocation points after adding");

        console.log("ID: DM_ADR_3");
        console.log("total allocation fee is updated when called by governance role");
        uint256 _allocationFeeAfter = sut.totalAllocationFee();
        assertEq(_allocationFeeBefore + _allocationFee2, _allocationFeeAfter, "allocation fee after adding");

        IDistributionManager.RecipientData[] memory _recipients = sut.getRecipients();
        console.log("ID: DM_ADR_4");
        console.log("recipients address is stored in the recipients array");
        assertEq(_recipients[1].destination, _destination2);
        assertTrue(
            _recipients[0].destination != _recipients[1].destination, "index 0 destination != index 1 destination"
        );

        console.log("ID: DM_ADR_5");
        console.log("recipients allocationPoints is stored in the recipients array");
        assertEq(_recipients[1].allocationPoints, _allocationPoints2);
        assertTrue(
            _recipients[0].allocationPoints != _recipients[1].allocationPoints,
            "index 0 allocationPoints != index 1 allocationPoints"
        );

        console.log("ID: DM_ADR_6");
        console.log("recipients allocationFee is stored in the recipients array");
        assertEq(_recipients[1].allocationFee, _allocationFee2);
        assertTrue(
            _recipients[0].allocationFee != _recipients[1].allocationFee,
            "index 0 allocationFee != index 1 allocationFee"
        );
    }

    function testAddDistrRecipient_DistributeRewards() public {
        console.log("ID: DM_ADR_11");
        console.log("distributeRewards is called and distributes the correct rewards");
        deal(address(structToken), address(sut), queuedNative);
        deal(address(nativeToken), address(sut), queuedNative);

        address _destination2 = vm.addr(0xd);
        uint256 _allocationPoints2 = 2e3;
        uint256 _allocationFee2 = 2e3;

        uint256 _recipient0StructBalanceBefore = structToken.balanceOf(recipient1.destination);
        uint256 _recipient0NativeBalanceBefore = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocationPointsTotal = sut.totalAllocationPoints();
        uint256 _allocationFeesTotal = sut.totalAllocationFee();

        uint256 _warpTime = 100 seconds;
        vm.warp(_warpTime);
        uint256 _lastUpdateTime = sut.lastUpdateTime();
        uint256 timeElapsed = block.timestamp - _lastUpdateTime;

        vm.prank(mockProduct);
        sut.queueFees(queuedNative);

        sut.addDistributionRecipient(_destination2, _allocationPoints2, _allocationFee2);

        uint256 _recipient0StructBalanceAfter = structToken.balanceOf(recipient1.destination);
        uint256 _allocatedTokens = (timeElapsed * rewardsPerSec * recipient1.allocationPoints) / _allocationPointsTotal;
        assertTrue(
            _recipient0StructBalanceAfter > _recipient0StructBalanceBefore,
            "recipient 0 struct token bal before > bal after"
        );
        assertEq(
            _recipient0StructBalanceAfter,
            _allocatedTokens + _recipient0StructBalanceBefore,
            "recipient 0 struct token expected bal after"
        );

        uint256 _recipient0NativeBalanceAfter = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocatedFees = (queuedNative * recipient1.allocationFee) / _allocationFeesTotal;
        assertTrue(
            _recipient0NativeBalanceAfter > _recipient0NativeBalanceBefore,
            "recipient 0 native token bal before > bal after"
        );
        assertEq(
            _recipient0NativeBalanceAfter,
            _allocatedFees + _recipient0NativeBalanceBefore,
            "recipient 0 native token expected bal after"
        );
    }

    function testAddDistrRecipient_RevertACL() public {
        console.log("ID: DM_ADR_8");
        console.log("should revert with error ACE_INVALID_ACCESS if called by non-governance role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.addDistributionRecipient(destination, allocationPoints, allocationFee);
    }

    function testAddDistrRecipient_RevertInvalidAllocation() public {
        console.log("ID: DM_ADR_9");
        console.log("should revert with error VE_INVALID_ALLOCATION if allocationPoints and allocationFee are zero");
        uint256 _allocationPoints = 0;
        uint256 _allocationFee = 0;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ALLOCATION));
        sut.addDistributionRecipient(destination, _allocationPoints, _allocationFee);
    }

    function testAddDistrRecipient_RevertInvalidDestination() public {
        console.log("ID: DM_ADR_10");
        console.log("should revert with error AE_ZERO_ADDRESS if destination is zero address");
        mockTokenBalances(queuedNative);
        address _destination = address(0);
        vm.expectRevert(abi.encodePacked(Errors.AE_ZERO_ADDRESS));
        sut.addDistributionRecipient(_destination, allocationPoints, allocationFee);
    }

    function testRemoveDistrRecipient_Success() public {
        mockTokenBalances(queuedNative);
        IDistributionManager.RecipientData memory _recipient0 = sut.getRecipients()[0];
        assertEq(sut.getRecipients().length, 1);
        uint256 _allocationPointsBefore = sut.totalAllocationPoints();
        uint256 _allocationFeeBefore = sut.totalAllocationFee();

        uint256 _recipientIndex = 0;
        sut.removeDistributionRecipient(_recipientIndex);

        console.log("ID: DM_RDR_1");
        console.log("recipients array decreases by 1");
        assertEq(sut.getRecipients().length, 0);

        console.log("ID: DM_RDR_2");
        console.log("total allocation points is updated when called by governance role");
        uint256 _allocationPointsAfter = sut.totalAllocationPoints();
        assertEq(_allocationPointsBefore - _recipient0.allocationPoints, _allocationPointsAfter);

        console.log("ID: DM_RDR_3");
        console.log("total allocation fee is updated when called by governance role");
        uint256 _allocationFeeAfter = sut.totalAllocationFee();
        assertEq(_allocationFeeBefore - _recipient0.allocationFee, _allocationFeeAfter);
    }

    function testRemoveDistrRecipient_RevertACL() public {
        console.log("ID: DM_RDR_4");
        console.log("should revert with error ACE_INVALID_ACCESS if called by non-governance role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        uint256 _recipientIndex = 0;
        user1.removeDistributionRecipient(_recipientIndex);
    }

    function testRemoveDistrRecipient_RevertInvalidIndex() public {
        console.log("ID: DM_RDR_5");
        console.log("should revert with error VE_INVALID_INDEX if index is larger than the recipients length array");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_INDEX));
        uint256 _recipientIndex = 1;
        sut.removeDistributionRecipient(_recipientIndex);
    }

    function testRemoveDistrRecipient_DistributeRewards() public {
        console.log("ID: DM_RDR_6");
        console.log("distributeRewards is called and distributes the correct rewards");
        deal(address(structToken), address(sut), queuedNative);
        deal(address(nativeToken), address(sut), queuedNative);

        uint256 _recipient0StructBalanceBefore = structToken.balanceOf(recipient1.destination);
        uint256 _recipient0NativeBalanceBefore = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocationPointsTotal = sut.totalAllocationPoints();
        uint256 _allocationFeesTotal = sut.totalAllocationFee();

        uint256 _warpTime = 100 seconds;
        vm.warp(_warpTime);
        uint256 _lastUpdateTime = sut.lastUpdateTime();
        uint256 timeElapsed = block.timestamp - _lastUpdateTime;

        vm.prank(mockProduct);
        sut.queueFees(queuedNative);

        uint256 _indexToRemove = 0;
        sut.removeDistributionRecipient(_indexToRemove);

        uint256 _recipient0StructBalanceAfter = structToken.balanceOf(recipient1.destination);
        uint256 _allocatedTokens = (timeElapsed * rewardsPerSec * recipient1.allocationPoints) / _allocationPointsTotal;
        assertTrue(
            _recipient0StructBalanceAfter > _recipient0StructBalanceBefore,
            "recipient 0 struct token bal before > bal after"
        );
        assertEq(
            _recipient0StructBalanceAfter,
            _allocatedTokens + _recipient0StructBalanceBefore,
            "recipient 0 struct token expected bal after"
        );

        uint256 _recipient0NativeBalanceAfter = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocatedFees = (queuedNative * recipient1.allocationFee) / _allocationFeesTotal;
        assertTrue(
            _recipient0NativeBalanceAfter > _recipient0NativeBalanceBefore,
            "recipient 0 native token bal before > bal after"
        );
        assertEq(
            _recipient0NativeBalanceAfter,
            _allocatedFees + _recipient0NativeBalanceBefore,
            "recipient 0 native token expected bal after"
        );
    }

    function testEditDistrRecipient_Success() public {
        mockTokenBalances(queuedNative);
        IDistributionManager.RecipientData memory _recipient0Before = sut.getRecipients()[0];
        uint256 _recipientIndex = 0;
        address _destination2 = vm.addr(0xe);

        console.log("ID: DM_EDR_11");
        console.log("only allocationPoints is zero");
        uint256 _allocationPoints2 = 0;
        uint256 _allocationFee2 = 2e8;
        uint256 _totalAllocationPointsBefore = sut.totalAllocationPoints();
        uint256 _totalAllocationFeeBefore = sut.totalAllocationFee();

        assertEq(sut.getRecipients().length, 1);

        console.log("ID: DM_EDR_6");
        console.log("totalAllocationPoints is updated");
        vm.expectEmit(true, true, true, true);
        emit EditRecipient(_recipientIndex, _destination2, _allocationPoints2, _allocationFee2);
        sut.editDistributionRecipient(_recipientIndex, _destination2, _allocationPoints2, _allocationFee2);
        IDistributionManager.RecipientData memory _recipient0After = sut.getRecipients()[0];

        console.log("ID: DM_EDR_1");
        console.log("recipient destination address is updated");
        assertEq(_recipient0After.destination, _destination2);
        assertTrue(_recipient0Before.destination != _recipient0After.destination);

        console.log("ID: DM_EDR_2");
        console.log("recipient allocationPoints is updated");
        assertEq(_recipient0After.allocationPoints, _allocationPoints2);
        assertTrue(_recipient0Before.allocationPoints != _recipient0After.allocationPoints);

        console.log("ID: DM_EDR_3");
        console.log("recipient allocationFee is updated");
        assertEq(_recipient0After.allocationFee, _allocationFee2);
        assertTrue(_recipient0Before.allocationFee != _recipient0After.allocationFee);

        console.log("ID: DM_EDR_4");
        console.log("totalAllocationPoints is updated");
        uint256 _totalAllocationPointsAfter = sut.totalAllocationPoints();
        assertEq(
            _totalAllocationPointsBefore + _allocationPoints2 - _recipient0Before.allocationPoints,
            _totalAllocationPointsAfter
        );
        assertTrue(_totalAllocationPointsAfter != _totalAllocationPointsBefore);

        console.log("ID: DM_EDR_5");
        console.log("totalAllocationFee is updated");
        uint256 _totalAllocationFeeAfter = sut.totalAllocationFee();
        assertEq(
            _totalAllocationFeeBefore + _allocationFee2 - _recipient0Before.allocationFee, _totalAllocationFeeAfter
        );
        assertTrue(_totalAllocationFeeAfter != _totalAllocationFeeBefore);
    }

    function testEditDistrRecipient_RevertACL() public {
        console.log("ID: DM_EDR_7");
        console.log("should revert with error ACE_INVALID_ACCESS if called by non-governance role");
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        uint256 _recipientIndex = 0;
        user1.editDistributionRecipient(_recipientIndex, destination, allocationPoints, allocationFee);
    }

    function testEditDistrRecipient_RevertInvalidIndex() public {
        console.log("ID: DM_EDR_8");
        console.log("should revert with error VE_INVALID_INDEX if index is larger than the recipients length array");
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_INDEX));
        uint256 _recipientIndex = 1;
        sut.editDistributionRecipient(_recipientIndex, destination, allocationPoints, allocationFee);
    }

    function testEditDistrRecipient_RevertInvalidAllocation() public {
        console.log("ID: DM_EDR_9");
        console.log("should revert with error VE_INVALID_ALLOCATION if allocationPoints and allocationFee are zero");
        uint256 _recipientIndex = 0;
        uint256 _allocationPoints = 0;
        uint256 _allocationFee = 0;
        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_ALLOCATION));
        sut.editDistributionRecipient(_recipientIndex, destination, _allocationPoints, _allocationFee);
    }

    function testEditDistrRecipient_RevertInvalidDestination() public {
        console.log("ID: DM_EDR_10");
        console.log("should revert with error AE_ZERO_ADDRESS if destination is zero address");
        uint256 _recipientIndex = 0;
        address _destination = address(0);
        vm.expectRevert(abi.encodePacked(Errors.AE_ZERO_ADDRESS));
        sut.editDistributionRecipient(_recipientIndex, _destination, allocationPoints, allocationFee);
    }

    function testEditDistrRecipient_DistributeRewards() public {
        console.log("ID: DM_EDR_12");
        console.log("distributeRewards is called and distributes the correct rewards");
        deal(address(structToken), address(sut), queuedNative);
        deal(address(nativeToken), address(sut), queuedNative);

        address _destination2 = vm.addr(0xd);
        uint256 _allocationPoints2 = 2e3;
        uint256 _allocationFee2 = 2e3;

        uint256 _recipient0StructBalanceBefore = structToken.balanceOf(recipient1.destination);
        uint256 _recipient0NativeBalanceBefore = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocationPointsTotal = sut.totalAllocationPoints();
        uint256 _allocationFeesTotal = sut.totalAllocationFee();

        uint256 _warpTime = 100 seconds;
        vm.warp(_warpTime);
        uint256 _lastUpdateTime = sut.lastUpdateTime();
        uint256 timeElapsed = block.timestamp - _lastUpdateTime;

        vm.prank(mockProduct);
        sut.queueFees(queuedNative);

        uint256 _indexToEdit = 0;
        sut.editDistributionRecipient(_indexToEdit, _destination2, _allocationPoints2, _allocationFee2);

        uint256 _recipient0StructBalanceAfter = structToken.balanceOf(recipient1.destination);
        uint256 _allocatedTokens = (timeElapsed * rewardsPerSec * recipient1.allocationPoints) / _allocationPointsTotal;
        assertTrue(
            _recipient0StructBalanceAfter > _recipient0StructBalanceBefore,
            "recipient 0 struct token bal before > bal after"
        );
        assertEq(
            _recipient0StructBalanceAfter,
            _allocatedTokens + _recipient0StructBalanceBefore,
            "recipient 0 struct token expected bal after"
        );

        uint256 _recipient0NativeBalanceAfter = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocatedFees = (queuedNative * recipient1.allocationFee) / _allocationFeesTotal;
        assertTrue(
            _recipient0NativeBalanceAfter > _recipient0NativeBalanceBefore,
            "recipient 0 native token bal before > bal after"
        );
        assertEq(
            _recipient0NativeBalanceAfter,
            _allocatedFees + _recipient0NativeBalanceBefore,
            "recipient 0 native token expected bal after"
        );
    }

    function testDistributeRewards_Success() public {
        console.log("ID: DM_DR_1");
        console.log("Contract with notifyRewardAmount method will be distributed rewards");
        uint256 _recipient0StructBalanceBefore = structToken.balanceOf(recipient1.destination);
        uint256 _recipient0NativeBalanceBefore = nativeToken.balanceOf(recipient1.destination);
        uint256 _totalAllocationPoints = sut.totalAllocationPoints();
        uint256 _totalAllocationFees = sut.totalAllocationFee();

        uint256 _lastUpdateTime = sut.lastUpdateTime();

        mockTokenBalances(queuedNative);
        vm.warp(100 seconds);
        uint256 _timeElapsed = block.timestamp - _lastUpdateTime;

        sut.distributeRewards();

        uint256 _recipient0StructBalanceAfter = structToken.balanceOf(recipient1.destination);
        uint256 _allocatedTokens = (_timeElapsed * rewardsPerSec * recipient1.allocationPoints) / _totalAllocationPoints;

        assertTrue(
            _recipient0StructBalanceAfter > _recipient0StructBalanceBefore,
            "recipient 0 Struct balance before > balance after"
        );
        assertEq(
            _recipient0StructBalanceAfter,
            _allocatedTokens + _recipient0StructBalanceBefore,
            "Recipient 0 Struct token balance"
        );

        uint256 _recipient0NativeBalanceAfter = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocatedFees = (queuedNative * recipient1.allocationFee) / _totalAllocationFees;

        assertTrue(
            _recipient0NativeBalanceAfter > _recipient0NativeBalanceBefore,
            "recipient 0 Native balance before > balance after"
        );
        assertEq(
            _recipient0NativeBalanceAfter,
            _allocatedFees + _recipient0NativeBalanceBefore,
            "Recipient 0 Native token balance"
        );
    }

    function testDistributeRewards_RevertInvalidDistrFee() public {
        console.log("ID: DM_DR_4");
        console.log(
            "should fail with error VE_INVALID_DISTRIBUTION_FEE if contract balance of native token is less than total fee allocation"
        );
        uint256 _contractBalanceStruct = 10e18;
        uint256 _queuedNativeZero = 0;

        vm.clearMockedCalls();
        vm.prank(mockProduct);
        sut.queueFees(_contractBalanceStruct);

        vm.mockCall(
            address(structToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(_contractBalanceStruct)
        );

        vm.mockCall(
            address(nativeToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(_queuedNativeZero)
        );

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_DISTRIBUTION_FEE));
        sut.distributeRewards();
    }

    function testDistributeRewards_RevertInvalidDistrToken() public {
        console.log("ID: DM_DR_5");
        console.log(
            "should fail with error VE_INVALID_DISTRIBUTION_TOKEN if contract balance of native token is less than total fee allocation"
        );
        vm.warp(2 weeks);
        uint256 _contractBalanceStruct = 10;

        vm.prank(mockProduct);
        sut.queueFees(queuedNative);

        vm.clearMockedCalls();
        vm.mockCall(
            address(structToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(_contractBalanceStruct)
        );

        vm.mockCall(address(nativeToken), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(queuedNative));

        vm.expectRevert(abi.encodePacked(Errors.VE_INVALID_DISTRIBUTION_TOKEN));
        sut.distributeRewards();
    }

    function testSetRewardsPerSecond_Success() public {
        console.log("ID: DM_SRPS_1");
        console.log("should succeed if new rewards per second is set within bounds by governance role");
        mockTokenBalances(queuedNative);
        uint256 _rewardsPerSecOld = sut.rewardsPerSecond();
        uint256 _rewardsPerSecNew = 2;
        sut.setRewardsPerSecond(_rewardsPerSecNew);
        uint256 _rewardsPerSecSet = sut.rewardsPerSecond();
        assertEq(_rewardsPerSecNew, _rewardsPerSecSet, "New rewards per sec set");
        assertTrue(_rewardsPerSecNew != _rewardsPerSecOld, "New rewards per sec != old rewards per sec");
    }

    function testSetRewardsPerSecond_RevertACL() public {
        console.log("ID: DM_SRPS_3");
        console.log("should revert with error ACE_INVALID_ACCESS if called by non-governance role");
        uint256 _rewardsPerSecNew = 1;
        vm.expectRevert(abi.encodePacked(Errors.ACE_INVALID_ACCESS));
        user1.setRewardsPerSecond(_rewardsPerSecNew);
    }

    function testSetRewardsPerSecond_DistributeRewards() public {
        console.log("ID: DM_SRPS_4");
        console.log("distributeRewards is called and distributes the correct rewards");

        deal(address(structToken), address(sut), queuedNative);
        deal(address(nativeToken), address(sut), queuedNative);

        uint256 _recipient0StructBalanceBefore = structToken.balanceOf(recipient1.destination);
        uint256 _recipient0NativeBalanceBefore = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocationPointsTotal = sut.totalAllocationPoints();
        uint256 _allocationFeesTotal = sut.totalAllocationFee();

        uint256 _warpTime = 100 seconds;
        vm.warp(_warpTime);
        uint256 _lastUpdateTime = sut.lastUpdateTime();
        uint256 timeElapsed = block.timestamp - _lastUpdateTime;

        vm.prank(mockProduct);
        sut.queueFees(queuedNative);

        uint256 _rewardsPerSecNew = 2;
        sut.setRewardsPerSecond(_rewardsPerSecNew);

        uint256 _recipient0StructBalanceAfter = structToken.balanceOf(recipient1.destination);
        uint256 _allocatedTokens = (timeElapsed * rewardsPerSec * recipient1.allocationPoints) / _allocationPointsTotal;
        assertTrue(
            _recipient0StructBalanceAfter > _recipient0StructBalanceBefore,
            "recipient 0 struct token bal before > bal after"
        );
        assertEq(
            _recipient0StructBalanceAfter,
            _allocatedTokens + _recipient0StructBalanceBefore,
            "recipient 0 struct token expected bal after"
        );

        uint256 _recipient0NativeBalanceAfter = nativeToken.balanceOf(recipient1.destination);
        uint256 _allocatedFees = (queuedNative * recipient1.allocationFee) / _allocationFeesTotal;
        assertTrue(
            _recipient0NativeBalanceAfter > _recipient0NativeBalanceBefore,
            "recipient 0 native token bal before > bal after"
        );
        assertEq(
            _recipient0NativeBalanceAfter,
            _allocatedFees + _recipient0NativeBalanceBefore,
            "recipient 0 native token expected bal after"
        );
    }
}
