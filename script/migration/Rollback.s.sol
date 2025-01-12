// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {EternalStorage} from "../../src/storage/EternalStorage.sol";
import {SimpleAMMV1} from "../../src/v1/SimpleAMMV1.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {EmergencyMultiSig} from "../../src/EmergencyMultiSig.sol";

contract RollbackScript is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        uint256 deployerKey = helperConfig.deployerKey();

        address storageAddress = vm.envAddress("STORAGE_ADDRESS");
        address v1Implementation = vm.envAddress("V1_IMPLEMENTATION");
        address v2Implementation = vm.envAddress("V2_IMPLEMENTATION");
        address multisig = vm.envAddress("MULTISIG");
        SimpleAMMV1 ammV1 = SimpleAMMV1(v1Implementation);
        SimpleAMMV2 ammV2 = SimpleAMMV2(v2Implementation);
        require(keccak256(bytes(ammV1.getVersion())) == keccak256(bytes("1.0.0")), "Invalid V1 version");
        require(keccak256(bytes(ammV2.getVersion())) == keccak256(bytes("2.0.0")), "Invalid V2 version");

        vm.startBroadcast(deployerKey);

        // Pause V2
        ammV2.pause();
        require(ammV2.paused(), "V2 not paused");

        // Get storage contract
        EternalStorage store = EternalStorage(storageAddress);

        // Store current implementation for potential rollback
        require(store.logicContract() == v2Implementation, "Wrong current implementation");

        // Rollback to V1
        store.upgradeLogicContract(v1Implementation);
        require(store.logicContract() == v1Implementation, "Rollback failed");
        console2.log("storage Rollback to V1 implementation:", v1Implementation);

        // Initialize V1 with multisig
        SimpleAMMV1(address(store)).initialize(multisig);
        console2.log("Initialized V1 with multisig:", multisig);

        // Set executor
        EmergencyMultiSig(multisig).setExecutor(address(ammV1));
        require(address(EmergencyMultiSig(multisig).executor()) == address(ammV1), "Executor not set correctly");
        console2.log("Set executor:", address(ammV1));

        // Resume V1
        ammV1.unpause();
        require(!ammV1.paused(), "V1 not unpaused");

        vm.stopBroadcast();
    }
}
