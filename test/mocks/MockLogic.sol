// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EternalStorage} from "../../src/storage/EternalStorage.sol";

contract MockLogic {
    EternalStorage private store;

    constructor(address _store) {
        store = EternalStorage(_store);
    }

    function setTestUint(bytes32 key, uint256 value) external {
        store.setUint(key, value);
    }

    function setTestString(bytes32 key, string calldata value) external {
        store.setString(key, value);
    }

    // Add other test methods as needed
}
