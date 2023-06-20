pragma solidity 0.8.11;

import "forge-std/src/Test.sol";
import "@core/common/GlobalAccessControl.sol";

contract BaseTestSetup is Test {
    GlobalAccessControl internal gac;

    address internal admin;
    address internal user1;
    address internal user2;
    address internal pauser;

    address internal mockFactory;
    address internal mockProduct;
    address internal mockProduct2;
    address internal mockProduct3;

    uint256 private nonce = 1;

    bytes32 public constant FACTORY = keccak256("FACTORY");
    bytes32 public constant PRODUCT = keccak256("PRODUCT");
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant KEEPER = keccak256("KEEPER");

    function setUp() public virtual {
        initContracts();
        setContractsLabels();
        grantRoles();
        onSetup();
    }

    function onSetup() public virtual {}

    function initContracts() internal {
        user1 = getNextAddress();
        user2 = getNextAddress();
        admin = getNextAddress();
        pauser = getNextAddress();

        mockFactory = getNextAddress();
        mockProduct = getNextAddress();
        mockProduct2 = getNextAddress();
        mockProduct3 = getNextAddress();

        vm.prank(admin);
        gac = new GlobalAccessControl(admin);
    }

    function setContractsLabels() internal {
        vm.label(admin, "Admin");
        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
        vm.label(pauser, "Pauser");

        vm.label(address(gac), "GAC");
        vm.label(address(this), "BaseSetup Contract");
        vm.label(mockFactory, "FEYProductFactory");
        vm.label(mockProduct, "FEYProduct");
        vm.label(mockProduct2, "FEYProduct2");
        vm.label(mockProduct3, "FEYProduct3");
    }

    function grantRoles() internal {
        vm.startPrank(admin);
        gac.grantRole(FACTORY, mockFactory);
        gac.grantRole(PAUSER, pauser);
        gac.grantRole(KEEPER, address(this));
        vm.stopPrank();
        vm.startPrank(mockFactory);
        gac.grantRole(PRODUCT, mockProduct);
        gac.grantRole(PRODUCT, mockProduct2);
        gac.grantRole(PRODUCT, mockProduct3);

        vm.stopPrank();
    }

    function getNextAddress() internal returns (address) {
        return vm.addr(nonce++);
    }
}
