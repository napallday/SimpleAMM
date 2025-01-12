// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EternalStorage} from "../../src/storage/EternalStorage.sol";
import {MockLogic} from "../mocks/MockLogic.sol";

contract EternalStorageTest is Test {
    EternalStorage public store;
    MockLogic public logic;
    address public admin;
    address public user;

    bytes32 constant TEST_KEY = keccak256("TEST_KEY");

    event LogicContractUpdated(address indexed oldLogic, address indexed newLogic);

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");

        vm.startPrank(admin);
        store = new EternalStorage(admin);
        logic = new MockLogic(address(store));
        store.upgradeLogicContract(address(logic));
        vm.stopPrank();
    }

    // ======== Admin Tests ========
    function testConstructor() public view {
        assertTrue(store.hasRole(store.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(store.hasRole(store.DEFAULT_ADMIN_ROLE(), address(0)));
    }

    function testConstructorZeroAddressReverts() public {
        vm.expectRevert(EternalStorage.ZeroAddress.selector);
        new EternalStorage(address(0));
    }

    function testUpgradeLogicContract() public {
        address newLogic = makeAddr("newLogic");

        vm.startPrank(admin);
        vm.expectEmit(true, true, false, false);
        emit LogicContractUpdated(address(logic), newLogic);
        store.upgradeLogicContract(newLogic);
        vm.stopPrank();

        assertEq(store.logicContract(), newLogic);
    }

    function testUpgradeLogicContractUnauthorized() public {
        address newLogic = makeAddr("newLogic");

        vm.startPrank(user);
        vm.expectRevert();
        store.upgradeLogicContract(newLogic);
        vm.stopPrank();
    }

    function testUpgradeLogicContractZeroAddressReverts() public {
        vm.startPrank(admin);
        vm.expectRevert(EternalStorage.ZeroAddress.selector);
        store.upgradeLogicContract(address(0));
        vm.stopPrank();
    }

    // ======== Storage Tests ========

    // Uint Storage Tests
    function testUintStorage() public {
        uint256 testValue = 123;

        vm.startPrank(address(logic));
        store.setUint(TEST_KEY, testValue);
        assertEq(store.getUint(TEST_KEY), testValue);

        store.deleteUint(TEST_KEY);
        assertEq(store.getUint(TEST_KEY), 0);
        vm.stopPrank();
    }

    function testUintStorageUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setUint(TEST_KEY, 123);
        vm.stopPrank();
    }

    // String Storage Tests
    function testStringStorage() public {
        string memory testValue = "Hello World";

        vm.startPrank(address(logic));
        store.setString(TEST_KEY, testValue);
        assertEq(store.getString(TEST_KEY), testValue);

        store.deleteString(TEST_KEY);
        assertEq(store.getString(TEST_KEY), "");
        vm.stopPrank();
    }

    function testStringStorageUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setString(TEST_KEY, "Hello World");
        vm.stopPrank();
    }

    // Address Storage Tests
    function testAddressStorage() public {
        address testValue = makeAddr("test");

        vm.startPrank(address(logic));
        store.setAddress(TEST_KEY, testValue);
        assertEq(store.getAddress(TEST_KEY), testValue);

        store.deleteAddress(TEST_KEY);
        assertEq(store.getAddress(TEST_KEY), address(0));
        vm.stopPrank();
    }

    function testAddressStorageUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setAddress(TEST_KEY, makeAddr("test"));
        vm.stopPrank();
    }

    // Bool Storage Tests
    function testBoolStorage() public {
        vm.startPrank(address(logic));
        store.setBool(TEST_KEY, true);
        assertTrue(store.getBool(TEST_KEY));

        store.deleteBool(TEST_KEY);
        assertFalse(store.getBool(TEST_KEY));
        vm.stopPrank();
    }

    function testBoolStorageUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setBool(TEST_KEY, true);
        vm.stopPrank();
    }

    // Bytes Storage Tests
    function testBytesStorage() public {
        bytes memory testValue = abi.encode("test");

        vm.startPrank(address(logic));
        store.setBytes(TEST_KEY, testValue);
        assertEq(store.getBytes(TEST_KEY), testValue);

        store.deleteBytes(TEST_KEY);
        assertEq(store.getBytes(TEST_KEY), "");
        vm.stopPrank();
    }

    function testBytesStorageUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setBytes(TEST_KEY, abi.encode("test"));
        vm.stopPrank();
    }

    // Int Storage Tests
    function testIntStorage() public {
        int256 testValue = -123;

        vm.startPrank(address(logic));
        store.setInt(TEST_KEY, testValue);
        assertEq(store.getInt(TEST_KEY), testValue);

        store.deleteInt(TEST_KEY);
        assertEq(store.getInt(TEST_KEY), 0);
        vm.stopPrank();
    }

    function testIntStorageUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setInt(TEST_KEY, -123);
        vm.stopPrank();
    }

    // the previous logic contract cannot call storage functions
    function testPreviousLogicContractCannotCallStorageFunctions() public {
        address newLogic = makeAddr("newLogic");
        vm.startPrank(admin);
        store.upgradeLogicContract(newLogic);
        vm.stopPrank();

        vm.startPrank(address(logic));
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        store.setUint(TEST_KEY, 123);
        vm.stopPrank();
    }

    function testMultipleStorageTypes() public {
        vm.startPrank(address(logic));

        // Set multiple storage types
        store.setUint(TEST_KEY, 123);
        store.setString(TEST_KEY, "test");
        store.setBool(TEST_KEY, true);
        store.setInt(TEST_KEY, -123);

        // Verify independence of storage
        assertEq(store.getUint(TEST_KEY), 123);
        assertEq(store.getString(TEST_KEY), "test");
        assertTrue(store.getBool(TEST_KEY));
        assertEq(store.getInt(TEST_KEY), -123);

        vm.stopPrank();
    }

    // ======== Fuzz Tests ========

    function testFuzz_UintStorage(bytes32 key, uint256 value) public {
        vm.startPrank(address(logic));
        store.setUint(key, value);
        assertEq(store.getUint(key), value);
        vm.stopPrank();
    }

    function testFuzz_IntStorage(bytes32 key, int256 value) public {
        vm.startPrank(address(logic));
        store.setInt(key, value);
        assertEq(store.getInt(key), value);
        vm.stopPrank();
    }

    function testFuzz_AddressStorage(bytes32 key, address value) public {
        vm.assume(value != address(0)); // Avoid zero address

        vm.startPrank(address(logic));
        store.setAddress(key, value);
        assertEq(store.getAddress(key), value);
        vm.stopPrank();
    }

    function testFuzz_BoolStorage(bytes32 key, bool value) public {
        vm.startPrank(address(logic));
        store.setBool(key, value);
        assertEq(store.getBool(key), value);
        vm.stopPrank();
    }

    function testFuzz_BytesStorage(bytes32 key, bytes memory value) public {
        vm.startPrank(address(logic));
        store.setBytes(key, value);
        assertEq(store.getBytes(key), value);
        vm.stopPrank();
    }

    function testFuzz_StringStorage(bytes32 key, string memory value) public {
        vm.startPrank(address(logic));
        store.setString(key, value);
        assertEq(store.getString(key), value);
        vm.stopPrank();
    }

    // ======== Stress Tests ========

    function testStressStorage() public {
        vm.startPrank(address(logic));

        for (uint256 i = 0; i < 100; i++) {
            bytes32 key = keccak256(abi.encode(i));
            store.setUint(key, i);
            store.setString(key, string(abi.encode(i)));
            store.setBool(key, i % 2 == 0);
            store.setInt(key, int256(i) - 50);
        }

        for (uint256 i = 0; i < 100; i++) {
            bytes32 key = keccak256(abi.encode(i));
            assertEq(store.getUint(key), i);
            assertEq(store.getBool(key), i % 2 == 0);
            assertEq(store.getInt(key), int256(i) - 50);
        }

        vm.stopPrank();
    }
}
