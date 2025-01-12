// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {DeploySimpleAMM} from "../../script/DeploySimpleAMM.s.sol";
import {EternalStorage} from "../../src/storage/EternalStorage.sol";
import {EmergencyMultiSig} from "../../src/EmergencyMultiSig.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {LPToken} from "../../src/LPToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract SimpleAMMV2Handler is Test {
    SimpleAMMV2 public amm;
    EternalStorage public store;
    EmergencyMultiSig public emergencyMultiSig;
    MockERC20 public token;
    HelperConfig public helperConfig;
    address public user;

    // Ghost Variables for tracking state
    uint256 public ghostLastProduct;

    // Bounds for operations
    uint256 public constant MIN_ETH_AMOUNT = 0.000_000_1 ether;
    uint256 public constant MAX_ETH_AMOUNT = 1 ether;
    uint256 public constant MIN_TOKEN_AMOUNT = 0.000_1 ether;
    uint256 public constant MAX_TOKEN_AMOUNT = 100_000 ether;

    constructor() {
        DeploySimpleAMM deployer = new DeploySimpleAMM();
        (amm, store, emergencyMultiSig, helperConfig) = deployer.run();
        user = makeAddr("user");

        // add liquidity first
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        token = new MockERC20();
        token.mint(user, 10000 ether);
        token.approve(address(amm), 10000 ether);
        amm.addLiquidity{value: 10 ether}(address(token), 10_000 ether);
        vm.stopPrank();

        // Initialize K value
        (uint256 tokenReserve, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        ghostLastProduct = tokenReserve * ethReserve;
    }

    // Add liquidity with random amounts
    function addLiquidity(uint256 ethAmount, uint256 tokenAmount) public {
        // Bound the input values
        ethAmount = bound(ethAmount, MIN_ETH_AMOUNT, MAX_ETH_AMOUNT);
        tokenAmount = bound(tokenAmount, MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);

        // Setup
        vm.startPrank(user);
        vm.deal(user, ethAmount);
        token.mint(user, tokenAmount);
        token.approve(address(amm), tokenAmount);

        // Action
        amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);

        vm.stopPrank();
    }

    // Remove liquidity with random shares
    function removeLiquidity(uint256 shares) public {
        vm.startPrank(user);
        address lpTokenAddr = amm.getLPTokenAddress(address(token));
        if (lpTokenAddr == address(0)) return;

        LPToken lpToken = LPToken(lpTokenAddr);
        uint256 balance = lpToken.balanceOf(user);
        if (balance == 0) return;

        // Bound shares to actual balance
        shares = bound(shares, 0, balance);
        if (shares == 0) return;

        amm.removeLiquidity(address(token), shares, 0, 0, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    // Swap ETH for tokens with random amounts
    function swapETHForTokens(uint256 ethAmount) public {
        (, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        vm.assume(ethReserve / 1000 > MIN_ETH_AMOUNT);
        ethAmount = bound(ethAmount, MIN_ETH_AMOUNT, ethReserve / 1000);

        vm.startPrank(user);
        vm.deal(user, ethAmount);

        amm.swapETHForTokens{value: ethAmount}(
            address(token),
            0, // minTokensOut
            2000, // maxSlippage 20%
            block.timestamp + 1 hours
        );

        vm.stopPrank();
        updateGhostVariablesAfterSwap();
    }

    // Swap tokens for ETH with random amounts
    function swapTokensForETH(uint256 tokenAmount) public {
        (uint256 tokenReserve,,) = amm.getPoolInfo(address(token));
        vm.assume(tokenReserve / 1000 > MIN_TOKEN_AMOUNT);
        tokenAmount = bound(tokenAmount, MIN_TOKEN_AMOUNT, tokenReserve / 1000);

        vm.startPrank(user);
        token.mint(user, tokenAmount);
        token.approve(address(amm), tokenAmount);

        amm.swapTokensForETH(
            address(token),
            tokenAmount,
            0, // minEthOut
            2000, // maxSlippage 20%
            block.timestamp + 1 hours
        );

        vm.stopPrank();
        updateGhostVariablesAfterSwap();
    }

    function updateGhostVariablesAfterSwap() internal {
        (uint256 tokenReserve, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        ghostLastProduct = tokenReserve * ethReserve;
    }
}
