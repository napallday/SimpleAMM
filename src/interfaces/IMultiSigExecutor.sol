// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMultiSigExecutor {
    /**
     * @notice Execute an emergency withdrawal of tokens or ETH
     * @param token The token address (address(0) for ETH)
     * @param to The recipient address
     * @param amount The amount to withdraw
     */
    function executeEmergencyWithdraw(address token, address to, uint256 amount) external;
}
