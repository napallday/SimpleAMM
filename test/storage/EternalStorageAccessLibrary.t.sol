// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/storage/EternalStorage.sol";
import "../../src/storage/EternalStorageAccessLibrary.sol";
import "../../src/LPToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract EternalStorageAccessLibraryTest is Test {
    using EternalStorageAccessLibrary for EternalStorage;

    EternalStorage public store;
    address public admin;
    address public logicContract;
    MockERC20 public token;
    address public user;
    address public lpToken;

    function setUp() public {
        admin = address(this);
        logicContract = makeAddr("logicContract");
        user = makeAddr("user");
        store = new EternalStorage(admin);
        store.upgradeLogicContract(logicContract);
        token = new MockERC20();
        lpToken = address(new LPToken("LP Token", "LP"));
    }

    function test_FeeManagement() public {
        uint256 newFee = 100; // 1%

        vm.startPrank(logicContract);
        // Test setting fee
        EternalStorageAccessLibrary.setFee(store, newFee);

        // Test getting fee
        uint256 retrievedFee = EternalStorageAccessLibrary.getFee(store);
        assertEq(retrievedFee, newFee, "Fee not set correctly");
        vm.stopPrank();
    }

    function test_FeeManagementUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        EternalStorageAccessLibrary.setFee(store, 100);
        vm.stopPrank();
    }

    function test_EmergencyMultiSig() public {
        address multiSig = makeAddr("multiSig");

        vm.startPrank(logicContract);
        // Test setting emergency multisig
        EternalStorageAccessLibrary.setEmergencyMultiSig(store, multiSig);

        // Test getting emergency multisig
        address retrievedMultiSig = EternalStorageAccessLibrary.getEmergencyMultiSig(store);
        assertEq(retrievedMultiSig, multiSig, "Emergency multisig not set correctly");
        vm.stopPrank();
    }

    function test_PoolOperations() public {
        vm.startPrank(logicContract);
        uint256 tokenReserve = 1000 ether;
        uint256 ethReserve = 2 ether;

        // Test setting full pool
        EternalStorageAccessLibrary.setPoolWithAddress(store, address(token), tokenReserve, ethReserve, lpToken);

        // Test getting full pool
        (uint256 retrievedTokenReserve, uint256 retrievedEthReserve, address retrievedLpToken) =
            EternalStorageAccessLibrary.getPoolWithAddress(store, address(token));

        assertEq(retrievedTokenReserve, tokenReserve, "Token reserve not set correctly");
        assertEq(retrievedEthReserve, ethReserve, "ETH reserve not set correctly");
        assertEq(retrievedLpToken, lpToken, "LP token not set correctly");

        // Test individual setters and getters
        uint256 newTokenReserve = 1500 ether;
        EternalStorageAccessLibrary.setPoolTokenReservesWithAddress(store, address(token), newTokenReserve);
        assertEq(
            EternalStorageAccessLibrary.getPoolTokenReservesWithAddress(store, address(token)),
            newTokenReserve,
            "Individual token reserve update failed"
        );

        uint256 newEthReserve = 3 ether;
        EternalStorageAccessLibrary.setPoolEthReservesWithAddress(store, address(token), newEthReserve);
        assertEq(
            EternalStorageAccessLibrary.getPoolEthReservesWithAddress(store, address(token)),
            newEthReserve,
            "Individual ETH reserve update failed"
        );

        address newLpToken = address(new LPToken("New LP Token", "NLP"));
        EternalStorageAccessLibrary.setPoolLPTokenWithAddress(store, address(token), newLpToken);
        assertEq(
            EternalStorageAccessLibrary.getPoolLPTokenWithAddress(store, address(token)),
            newLpToken,
            "Individual LP token update failed"
        );

        // Test pool deletion
        EternalStorageAccessLibrary.deletePoolWithAddress(store, address(token));
        (uint256 deletedTokenReserve, uint256 deletedEthReserve, address deletedLpToken) =
            EternalStorageAccessLibrary.getPoolWithAddress(store, address(token));

        assertEq(deletedTokenReserve, 0, "Token reserve not deleted");
        assertEq(deletedEthReserve, 0, "ETH reserve not deleted");
        assertEq(deletedLpToken, address(0), "LP token not deleted");
        vm.stopPrank();
    }

    function test_PoolOperationsUnauthorized_TokenReserve() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        EternalStorageAccessLibrary.setPoolTokenReservesWithAddress(store, address(token), 1000 ether);
        vm.stopPrank();
    }

    function test_PoolOperationsUnauthorized_EthReserve() public {
        vm.startPrank(user);
        vm.expectRevert(EternalStorage.NotAuthorizedLogic.selector);
        EternalStorageAccessLibrary.setPoolEthReservesWithAddress(store, address(token), 2 ether);
        vm.stopPrank();
    }
}
