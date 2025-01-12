// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {EternalStorage} from "../../src/storage/EternalStorage.sol";
import {SimpleAMMV1} from "../../src/v1/SimpleAMMV1.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract UnpauseV2Script is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        uint256 deployerKey = helperConfig.deployerKey();

        address v2Implementation = vm.envAddress("V2_IMPLEMENTATION");
        SimpleAMMV2 ammV2 = SimpleAMMV2(v2Implementation);
        require(keccak256(bytes(ammV2.getVersion())) == keccak256(bytes("2.0.0")), "Invalid V2 version");

        vm.startBroadcast(deployerKey);

        // Unpause V2
        ammV2.unpause();
        require(!ammV2.paused(), "V2 not unpaused");

        vm.stopBroadcast();
    }
}
