// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EternalStorage
 * @notice Pure storage contract with basic storage functionality and upgrade mechanism
 * @dev Implements a pattern where storage is separated from logic to enable upgrades
 */
contract EternalStorage is AccessControl, Pausable {
    // Errors

    /// @notice Thrown when non-logic contract attempts to access storage
    error NotAuthorizedLogic();
    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Address of the current logic contract
    address public logicContract;

    // Primitive type storage
    // @dev Mapping storage for uint256, string, address, bool, bytes, and int256
    mapping(bytes32 => uint256) private uintStorage;
    mapping(bytes32 => string) private stringStorage;
    mapping(bytes32 => address) private addressStorage;
    mapping(bytes32 => bool) private boolStorage;
    mapping(bytes32 => bytes) private bytesStorage;
    mapping(bytes32 => int256) private intStorage;

    // events

    /// @notice Emitted when logic contract is updated
    /// @param oldLogic Address of previous logic contract
    /// @param newLogic Address of new logic contract
    event LogicContractUpdated(address indexed oldLogic, address indexed newLogic);

    // modifiers
    /// @notice Ensures caller is the current logic contract
    modifier onlyLogic() {
        if (msg.sender != logicContract) revert NotAuthorizedLogic();
        _;
    }

    /// @notice Ensures provided address is not zero
    modifier notZeroAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    /// @notice Initializes contract with admin address
    /// @param admin Address to be granted admin role
    constructor(address admin) notZeroAddress(admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // external functions

    /// @notice Updates the logic contract address
    /// @param _logicContract Address of new logic contract
    /// @dev Can only be called by admin
    function upgradeLogicContract(address _logicContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        notZeroAddress(_logicContract)
    {
        address oldLogic = logicContract;
        logicContract = _logicContract;
        emit LogicContractUpdated(oldLogic, _logicContract);
    }

    function setUint(bytes32 key, uint256 value) external onlyLogic {
        uintStorage[key] = value;
    }

    function getUint(bytes32 key) external view returns (uint256) {
        return uintStorage[key];
    }

    function deleteUint(bytes32 key) external onlyLogic {
        delete uintStorage[key];
    }

    function setAddress(bytes32 key, address value) external onlyLogic {
        addressStorage[key] = value;
    }

    function getAddress(bytes32 key) external view returns (address) {
        return addressStorage[key];
    }

    function deleteAddress(bytes32 key) external onlyLogic {
        delete addressStorage[key];
    }

    function setBool(bytes32 key, bool value) external onlyLogic {
        boolStorage[key] = value;
    }

    function getBool(bytes32 key) external view returns (bool) {
        return boolStorage[key];
    }

    function deleteBool(bytes32 key) external onlyLogic {
        delete boolStorage[key];
    }

    function setBytes(bytes32 key, bytes calldata value) external onlyLogic {
        bytesStorage[key] = value;
    }

    function getBytes(bytes32 key) external view returns (bytes memory) {
        return bytesStorage[key];
    }

    function deleteBytes(bytes32 key) external onlyLogic {
        delete bytesStorage[key];
    }

    function setInt(bytes32 key, int256 value) external onlyLogic {
        intStorage[key] = value;
    }

    function getInt(bytes32 key) external view returns (int256) {
        return intStorage[key];
    }

    function deleteInt(bytes32 key) external onlyLogic {
        delete intStorage[key];
    }

    function setString(bytes32 key, string calldata value) external onlyLogic {
        stringStorage[key] = value;
    }

    function getString(bytes32 key) external view returns (string memory) {
        return stringStorage[key];
    }

    function deleteString(bytes32 key) external onlyLogic {
        delete stringStorage[key];
    }
}
