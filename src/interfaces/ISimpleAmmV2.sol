// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./ISimpleAmmV1.sol";

interface ISimpleAMMV2 is ISimpleAMMV1 {
    /*//////////////////////////////////////////////////////////////
                              ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setFee(uint256 newFee) external;
}
