// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMMV2Test} from "../SimpleAMMV2.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAMMV2FuzzTest is SimpleAMMV2Test {
    function testFuzz_AddLiquidity(uint256 ethAmount, uint256 tokenAmount) public {
        // Assumptions to bound inputs to reasonable ranges
        ethAmount = bound(ethAmount, 0.001 ether, 100 ether);
        tokenAmount = bound(tokenAmount, 0.001 ether, 100_000 ether);

        uint256 previousEthBalance = user2.balance;
        uint256 previousTokenBalance = token.balanceOf(user2);

        // Setup
        vm.startPrank(user2);

        // Action & Verification
        uint256 shares = amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);
        IERC20 lpToken = IERC20(amm.getLPTokenAddress(address(token)));

        // Assert invariants
        assertGt(shares, 0, "Shares should be greater than 0");
        assertEq(address(amm).balance, ethAmount, "AMM's ETH balance should increase");
        assertEq(token.balanceOf(address(amm)), tokenAmount, "AMM's token balance should increase");
        assertEq(user2.balance, previousEthBalance - ethAmount, "User2's ETH balance should decrease");
        assertEq(token.balanceOf(user2), previousTokenBalance - tokenAmount, "User2's token balance should decrease");
        assertEq(shares, lpToken.balanceOf(user2), "Shares should be equal to LP token balance");
    }

    function testFuzz_RemoveLiquidity(uint256 ethAmount, uint256 tokenAmount, uint256 sharesToRemove) public {
        // Setup initial liquidity
        ethAmount = bound(ethAmount, 0.001 ether, 1000 ether);
        tokenAmount = bound(tokenAmount, 0.001 ether, 1_000_000 ether);

        vm.startPrank(user2);

        uint256 shares = amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);
        sharesToRemove = bound(sharesToRemove, amm.MINIMUM_LIQUIDITY(), shares);

        // Action & Verification
        amm.removeLiquidity(
            address(token),
            sharesToRemove,
            0, // minEthOut
            0, // minTokensOut
            block.timestamp + 1 hours
        );

        // Assert invariants
        assertApproxEqAbs(address(amm).balance, ethAmount - sharesToRemove * ethAmount / shares, ethAmount / 10000);
        assertApproxEqAbs(
            token.balanceOf(address(amm)), tokenAmount - sharesToRemove * tokenAmount / shares, tokenAmount / 10000
        );
        assertApproxEqAbs(
            token.balanceOf(user2),
            INITIAL_USER_TOKEN_BALANCE - tokenAmount + sharesToRemove * tokenAmount / shares,
            tokenAmount / 10000
        );
    }

    function testFuzz_SwapETHForTokens(uint256 ethAmount) public {
        // Setup initial liquidity first
        add_Liquidity_user1();

        // Assumptions: below maximum eth amount: 1 ether
        // set low slippage
        ethAmount = bound(ethAmount, 0.00000001 ether, 0.01 ether);

        vm.startPrank(user2);

        uint256 balanceBefore = token.balanceOf(user2);

        amm.swapETHForTokens{value: ethAmount}(
            address(token),
            0, // minTokensOut
            200, // maxSlippage
            block.timestamp + 1 hours
        );

        assertGt(token.balanceOf(user2), balanceBefore);
    }

    function testFuzz_RevertIf_PriceImpactTooHigh_SwapETHForTokens(uint256 ethAmount) public {
        // Setup initial liquidity first
        add_Liquidity_user1();

        // Assumptions: below maximum eth amount: 1 ether
        // set high slippage
        ethAmount = bound(ethAmount, 0.3 ether, 0.999 ether);

        vm.startPrank(user2);

        vm.expectRevert();
        amm.swapETHForTokens{value: ethAmount}(
            address(token),
            0, // minTokensOut
            200, // maxSlippage
            block.timestamp + 1 hours
        );
    }

    function testFuzz_SwapTokensForETH(uint256 tokenAmount) public {
        // Setup initial liquidity
        add_Liquidity_user1();

        // set low token amount
        tokenAmount = bound(tokenAmount, 0.0001 ether, 1 ether);

        vm.startPrank(user2);
        uint256 balanceBefore = user2.balance;

        amm.swapTokensForETH(
            address(token),
            tokenAmount,
            0, // minEthOut
            200, // maxSlippage
            block.timestamp + 1 hours
        );

        assertGt(user2.balance, balanceBefore);
    }

    function testFuzz_RevertIf_PriceImpactTooHigh_SwapTokensForETH(uint256 tokenAmount) public {
        // Setup initial liquidity
        add_Liquidity_user1();

        // set low token amount
        tokenAmount = bound(tokenAmount, 30 ether, 122 ether);

        vm.startPrank(user2);

        vm.expectRevert();
        amm.swapTokensForETH(
            address(token),
            tokenAmount,
            0, // minEthOut
            200, // maxSlippage
            block.timestamp + 1 hours
        );
    }

    function testFuzz_SpotPrice(uint256 ethReserve, uint256 tokenReserve) public {
        // Setup with fuzzed reserves
        ethReserve = bound(ethReserve, 0.0001 ether, 100 ether);
        tokenReserve = bound(tokenReserve, 0.01 ether, 100_000 ether);

        vm.startPrank(user1);
        amm.addLiquidity{value: ethReserve}(address(token), tokenReserve);
        vm.stopPrank();

        uint256 spotPrice = amm.getSpotPrice(address(token));
        assertGt(spotPrice, 0);
    }
}
