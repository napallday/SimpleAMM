// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {EternalStorage} from "../src/storage/EternalStorage.sol";
import {EmergencyMultiSig} from "../src/EmergencyMultiSig.sol";
import {SimpleAMMV2} from "../src/v2/SimpleAMMV2.sol";

contract DeploySimpleAMM is Script {
    function run() external returns (SimpleAMMV2, EternalStorage, EmergencyMultiSig, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        address admin = helperConfig.admin();
        uint256 deployerKey = helperConfig.deployerKey();
        address[] memory operators = helperConfig.getOperators();
        address[] memory emergencyAdmins = helperConfig.getEmergencyAdmins();

        // todo: change to use KeyStore to replace private key
        vm.startBroadcast(deployerKey);

        // Deploy contracts
        EternalStorage eternalStorage = new EternalStorage(admin);
        // todo: edge case check no duplicate admins
        EmergencyMultiSig emergencyMultiSig = new EmergencyMultiSig(emergencyAdmins, emergencyAdmins.length / 2 + 1);

        SimpleAMMV2 simpleAmm = new SimpleAMMV2(admin, operators, emergencyAdmins, address(eternalStorage));

        // Set up logic contract for storage contract
        eternalStorage.upgradeLogicContract(address(simpleAmm));
        simpleAmm.initialize(address(emergencyMultiSig));
        emergencyMultiSig.setExecutor(address(simpleAmm));
        vm.stopBroadcast();

        return (simpleAmm, eternalStorage, emergencyMultiSig, helperConfig);
    }
}
