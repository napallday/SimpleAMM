// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {EternalStorage} from "../../src/storage/EternalStorage.sol";
import {SimpleAMMV1} from "../../src/v1/SimpleAMMV1.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {EmergencyMultiSig} from "../../src/EmergencyMultiSig.sol";

contract UpgradeToV2Script is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        uint256 deployerKey = helperConfig.deployerKey();

        address storageAddress = vm.envAddress("STORAGE_ADDRESS");
        address v1Implementation = vm.envAddress("V1_IMPLEMENTATION");
        address v2Implementation = vm.envAddress("V2_IMPLEMENTATION");
        address multisig = vm.envAddress("MULTISIG");
        SimpleAMMV1 ammV1 = SimpleAMMV1(v1Implementation);
        SimpleAMMV2 ammV2 = SimpleAMMV2(v2Implementation);

        // Check versions using keccak256 for string comparison
        require(keccak256(bytes(ammV1.getVersion())) == keccak256(bytes("1.0.0")), "Invalid V1 version");
        require(keccak256(bytes(ammV2.getVersion())) == keccak256(bytes("2.0.0")), "Invalid V2 version");

        vm.startBroadcast(deployerKey);

        // Pause V1
        ammV1.pause();
        require(ammV1.paused(), "V1 not paused");

        // Get storage contract
        EternalStorage store = EternalStorage(storageAddress);

        // Store current implementation for potential rollback
        require(store.logicContract() == v1Implementation, "Wrong current implementation");

        // Upgrade to V2
        store.upgradeLogicContract(v2Implementation);
        require(store.logicContract() == v2Implementation, "Upgrade failed");
        console2.log("Storage upgraded to V2 implementation:", v2Implementation);

        // Initialize V2 with multisig
        SimpleAMMV2(address(store)).initialize(multisig);
        console2.log("Initialized V2 with multisig:", multisig);

        // Set executor
        EmergencyMultiSig(multisig).setExecutor(address(ammV2));
        require(address(EmergencyMultiSig(multisig).executor()) == address(ammV2), "Executor not set correctly");
        console2.log("Set executor:", address(ammV2));

        // Pause V2
        ammV2.pause();
        require(ammV2.paused(), "V2 not paused");

        vm.stopBroadcast();
    }
}
