// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../LPToken.sol";
import "./EternalStorage.sol";

/**
 * @title EternalStorageAccessLibrary
 * @notice Library providing structured access to EternalStorage contract
 * @dev Implements key generation and accessor functions for AMM storage
 */
library EternalStorageAccessLibrary {
    // Storage keys
    bytes32 private constant FEE_KEY = keccak256("simpleamm.fee");
    bytes32 private constant EMERGENCY_MULTISIG_KEY = keccak256("simpleamm.emergency_multisig");
    bytes32 private constant POOL_TOKEN_RESERVE_KEY = keccak256("simpleamm.pool.tokenReserve");
    bytes32 private constant POOL_ETH_RESERVE_KEY = keccak256("simpleamm.pool.ethReserve");
    bytes32 private constant POOL_LP_TOKEN_KEY = keccak256("simpleamm.pool.lpToken");

    // Pool storage key pattern
    /// @notice Generates storage key for token reserve
    /// @param token Address of the token
    /// @return Storage key for token reserve
    function poolTokenReserveKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(POOL_TOKEN_RESERVE_KEY, token));
    }

    /// @notice Generates storage key for ETH reserve
    /// @param token Address of the token in pair
    /// @return Storage key for ETH reserve
    function poolEthReserveKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(POOL_ETH_RESERVE_KEY, token));
    }

    /// @notice Generates storage key for LP token address
    /// @param token Address of the token in pair
    /// @return Storage key for LP token
    function poolLPTokenKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(POOL_LP_TOKEN_KEY, token));
    }

    // Fee functions
    /// @notice Gets current AMM fee
    /// @param store EternalStorage contract
    /// @return Current fee in basis points
    function getFee(EternalStorage store) internal view returns (uint256) {
        return store.getUint(FEE_KEY);
    }

    /// @notice Sets AMM fee
    /// @param store EternalStorage contract
    /// @param newFee New fee in basis points
    function setFee(EternalStorage store, uint256 newFee) internal {
        store.setUint(FEE_KEY, newFee);
    }

    // Emergency MultiSig functions
    /// @notice Gets emergency multisig address
    /// @param store EternalStorage contract
    /// @return Address of emergency multisig
    function getEmergencyMultiSig(EternalStorage store) internal view returns (address) {
        return store.getAddress(EMERGENCY_MULTISIG_KEY);
    }

    /// @notice Sets emergency multisig address
    /// @param store EternalStorage contract
    /// @param multiSig New multisig address
    function setEmergencyMultiSig(EternalStorage store, address multiSig) internal {
        store.setAddress(EMERGENCY_MULTISIG_KEY, multiSig);
    }

    // Pool functions
    /// @notice Gets all pool data for a token
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @return tokenReserve Current token reserve
    /// @return ethReserve Current ETH reserve
    /// @return lpToken LP token address
    function getPoolWithAddress(EternalStorage store, address tokenAddress)
        internal
        view
        returns (uint256 tokenReserve, uint256 ethReserve, address lpToken)
    {
        tokenReserve = store.getUint(poolTokenReserveKey(tokenAddress));
        ethReserve = store.getUint(poolEthReserveKey(tokenAddress));
        lpToken = store.getAddress(poolLPTokenKey(tokenAddress));
    }

    /// @notice Sets all pool data for a token
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @param tokenReserve New token reserve
    /// @param ethReserve New ETH reserve
    /// @param lpToken New LP token address
    function setPoolWithAddress(
        EternalStorage store,
        address tokenAddress,
        uint256 tokenReserve,
        uint256 ethReserve,
        address lpToken
    ) internal {
        store.setUint(poolTokenReserveKey(tokenAddress), tokenReserve);
        store.setUint(poolEthReserveKey(tokenAddress), ethReserve);
        store.setAddress(poolLPTokenKey(tokenAddress), lpToken);
    }

    /// @notice Deletes all pool data for a token
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    function deletePoolWithAddress(EternalStorage store, address tokenAddress) internal {
        store.deleteUint(poolTokenReserveKey(tokenAddress));
        store.deleteUint(poolEthReserveKey(tokenAddress));
        store.deleteAddress(poolLPTokenKey(tokenAddress));
    }

    /// @notice Sets token reserve for a pool
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @param tokenReserve New token reserve
    function setPoolTokenReservesWithAddress(EternalStorage store, address tokenAddress, uint256 tokenReserve)
        internal
    {
        store.setUint(poolTokenReserveKey(tokenAddress), tokenReserve);
    }

    /// @notice Sets ETH reserve for a pool
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @param ethReserve New ETH reserve
    function setPoolEthReservesWithAddress(EternalStorage store, address tokenAddress, uint256 ethReserve) internal {
        store.setUint(poolEthReserveKey(tokenAddress), ethReserve);
    }

    /// @notice Sets LP token address for a pool
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @param lpToken New LP token address
    function setPoolLPTokenWithAddress(EternalStorage store, address tokenAddress, address lpToken) internal {
        store.setAddress(poolLPTokenKey(tokenAddress), lpToken);
    }

    /// @notice Gets token reserve for a pool
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @return tokenReserve Current token reserve
    function getPoolTokenReservesWithAddress(EternalStorage store, address tokenAddress)
        internal
        view
        returns (uint256 tokenReserve)
    {
        tokenReserve = store.getUint(poolTokenReserveKey(tokenAddress));
    }

    /// @notice Gets ETH reserve for a pool
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @return ethReserve Current ETH reserve
    function getPoolEthReservesWithAddress(EternalStorage store, address tokenAddress)
        internal
        view
        returns (uint256 ethReserve)
    {
        ethReserve = store.getUint(poolEthReserveKey(tokenAddress));
    }

    /// @notice Gets LP token address for a pool
    /// @param store EternalStorage contract
    /// @param tokenAddress Token address
    /// @return lpToken LP token address
    function getPoolLPTokenWithAddress(EternalStorage store, address tokenAddress)
        internal
        view
        returns (address lpToken)
    {
        lpToken = store.getAddress(poolLPTokenKey(tokenAddress));
    }
}
