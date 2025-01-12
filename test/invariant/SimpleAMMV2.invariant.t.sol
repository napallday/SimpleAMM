// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMMV2Handler} from "./SimpleAMMV2Handler.t.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract SimpleAMMV2InvariantTest is Test {
    SimpleAMMV2Handler public handler;
    SimpleAMMV2 public amm;
    MockERC20 public token;
    address public user;
    HelperConfig public helperConfig;
    address public admin;
    address[] public emergencyAdmins;

    function setUp() public {
        handler = new SimpleAMMV2Handler();
        amm = handler.amm();
        token = handler.token();
        user = handler.user();
        helperConfig = handler.helperConfig();
        admin = helperConfig.admin();
        emergencyAdmins = helperConfig.getEmergencyAdmins();

        // Add initial liquidity to enable testing
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        token.mint(user, 10000 ether);
        token.approve(address(amm), 10000 ether);
        amm.addLiquidity{value: 10 ether}(address(token), 10000 ether);
        vm.stopPrank();

        // Target the handler contract for invariant testing
        targetContract(address(handler));
    }

    function invariant_RolesAndPermissions() public view {
        // Admin role should never be lost
        assert(amm.hasRole(amm.DEFAULT_ADMIN_ROLE(), admin));

        // Emergency admins should maintain their roles
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            assert(amm.hasRole(amm.EMERGENCY_ROLE(), emergencyAdmins[i]));
        }
    }

    function invariant_PausedStateConsistency() public {
        if (!amm.paused()) {
            vm.startPrank(admin);
            amm.pause();
            vm.stopPrank();
        }

        // If paused, certain operations should be impossible
        if (amm.paused()) {
            vm.expectRevert();
            amm.addLiquidity{value: 1 ether}(address(token), 100 ether);

            vm.expectRevert();
            amm.swapETHForTokens{value: 1 ether}(address(token), 0, 200, block.timestamp + 1);
        }
    }
}
