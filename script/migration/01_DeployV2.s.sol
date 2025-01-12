// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract DeployV2Script is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        address admin = helperConfig.admin();
        // todo: change to use KeyStore to replace private key
        uint256 deployerKey = helperConfig.deployerKey();
        address[] memory operators = helperConfig.getOperators();
        address[] memory emergencyAdmins = helperConfig.getEmergencyAdmins();
        address storageAddress = vm.envAddress("STORAGE_ADDRESS");

        vm.startBroadcast(deployerKey);
        // Deploy V2 implementation
        SimpleAMMV2 ammV2 = new SimpleAMMV2(admin, operators, emergencyAdmins, storageAddress);
        console2.log("SimpleAMMv2 deployed at:", address(ammV2));

        vm.stopBroadcast();
    }
}
