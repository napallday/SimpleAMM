// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    // struct NetworkConfig {
    //     address admin;
    //     // @todo: in the real project, use keystores instead of private keys·
    //     uint256 deployerKey;
    //     address[] moperators;
    //     address[] emergencyAdmins;·
    // }

    uint256 public constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public constant ANVIL_ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    address[] public ANIVIL_OPERATORS =
        [0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC];
    address[] public ANIVIL_EMERGENCY_ADMINS =
        [ANVIL_ADMIN, 0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC];

    // NetworkConfig public activeNetworkConfig;
    address public admin;
    uint256 public deployerKey;
    address[] public operators;
    address[] public emergencyAdmins;

    constructor() {
        if (block.chainid == 11_155_111) {
            createSepoliaEthConfig();
        } else if (block.chainid == 1) {
            createMainnetEthConfig();
        } else if (block.chainid == 31337) {
            createAnvilEthConfig();
        } else {
            revert("Unsupported network");
        }
    }

    function createSepoliaEthConfig() public {
        admin = vm.envAddress("SEPOLIA_ADMIN");
        deployerKey = vm.envUint("PRIVATE_KEY");
        operators = _parseAddressArray("SEPOLIA_OPERATORS");
        emergencyAdmins = _parseAddressArray("SEPOLIA_EMERGENCY_ADMINS");
    }

    function createMainnetEthConfig() public {
        admin = vm.envAddress("MAINNET_ADMIN");
        deployerKey = vm.envUint("PRIVATE_KEY");
        operators = _parseAddressArray("MAINNET_OPERATORS");
        emergencyAdmins = _parseAddressArray("MAINNET_EMERGENCY_ADMINS");
    }

    function createAnvilEthConfig() public {
        admin = ANVIL_ADMIN;
        deployerKey = ANVIL_DEFAULT_KEY;

        operators = ANIVIL_OPERATORS;

        emergencyAdmins = ANIVIL_EMERGENCY_ADMINS;
    }

    function _parseAddressArray(string memory envKey) internal view returns (address[] memory) {
        string[] memory addressStrings = vm.envString(envKey, ",");
        address[] memory addresses = new address[](addressStrings.length);
        for (uint256 i = 0; i < addressStrings.length; i++) {
            addresses[i] = vm.parseAddress(addressStrings[i]);
        }
        return addresses;
    }

    function getOperators() public view returns (address[] memory) {
        return operators;
    }

    function getEmergencyAdmins() public view returns (address[] memory) {
        return emergencyAdmins;
    }
}
