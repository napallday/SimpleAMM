// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMMV2Handler} from "./SimpleAMMV2Handler.t.sol";

contract SwapInvariantTest is Test {
    SimpleAMMV2Handler public handler;

    function setUp() public {
        handler = new SimpleAMMV2Handler();

        // Only target swap functions
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.swapETHForTokens.selector;
        selectors[1] = handler.swapTokensForETH.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SwapConstantProduct() public view {
        (uint256 tokenReserve, uint256 ethReserve,) = handler.amm().getPoolInfo(address(handler.token()));
        uint256 currentProduct = tokenReserve * ethReserve;
        uint256 lastProduct = handler.ghostLastProduct();

        // Current product should be greater than or equal to initial product
        // due to fees accumulating in the pool
        assertGe(currentProduct, lastProduct, "K should never decrease");

        // Allow for a maximum increase of 5% from initial product
        // This is a reasonable bound since fees are 0.3% per swap
        uint256 maxProduct = lastProduct * 105 / 100; // 105% of initial product
        assertLe(currentProduct, maxProduct, "K increased too much");
    }

    function invariant_callSummary() public view {
        console.log("product", handler.ghostLastProduct());
    }
}
