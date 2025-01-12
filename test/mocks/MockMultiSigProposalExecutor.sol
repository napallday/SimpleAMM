// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMultiSigExecutor} from "../../src/interfaces/IMultiSigExecutor.sol";

contract MockMultiSigProposalExecutor is IMultiSigExecutor {
    event EmergencyWithdrawExecuted(address token, address to, uint256 amount);

    function executeEmergencyWithdraw(address token, address to, uint256 amount) external {
        emit EmergencyWithdrawExecuted(token, to, amount);
    }
}
