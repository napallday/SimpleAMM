// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeploySimpleAMM} from "../script/DeploySimpleAMM.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {SimpleAMMV2} from "../src/v2/SimpleAMMV2.sol";
import {EternalStorage} from "../src/storage/EternalStorage.sol";
import {EmergencyMultiSig} from "../src/EmergencyMultiSig.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LPToken} from "../src/LPToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract SimpleAMMV2Test is Test {
    SimpleAMMV2 public amm;
    EternalStorage public store;
    EmergencyMultiSig public emergencyMultiSig;
    HelperConfig public helperConfig;
    MockERC20 public token;

    address public admin;
    address[] public operators;
    address[] public emergencyAdmins;
    uint256 public deployerKey;

    address public user1;
    address public user2;
    uint256 public constant INITIAL_USER_ETH_BALANCE = 10_000 ether;
    uint256 public constant INITIAL_USER_TOKEN_BALANCE = 1_000_000 ether;

    event LiquidityAdded(
        address indexed provider, address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 shares
    );
    event LiquidityRemoved(
        address indexed provider, address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 shares
    );
    event TokenSwap(address indexed token, uint256 tokenAmount, uint256 ethAmount);

    function setUp() public virtual {
        DeploySimpleAMM deployer = new DeploySimpleAMM();
        (amm, store, emergencyMultiSig, helperConfig) = deployer.run();
        admin = helperConfig.admin();
        deployerKey = helperConfig.deployerKey();
        operators = helperConfig.getOperators();
        emergencyAdmins = helperConfig.getEmergencyAdmins();

        // Set up test users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(user1, INITIAL_USER_ETH_BALANCE);
        vm.deal(user2, INITIAL_USER_ETH_BALANCE);

        // Deploy and set up mock token
        token = new MockERC20();
        token.mint(user1, INITIAL_USER_TOKEN_BALANCE);
        token.mint(user2, INITIAL_USER_TOKEN_BALANCE);

        // Approvals
        vm.startPrank(user1);
        token.approve(address(amm), INITIAL_USER_TOKEN_BALANCE);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(amm), INITIAL_USER_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function test_InitialSetup() public view {
        assert(amm.hasRole(amm.DEFAULT_ADMIN_ROLE(), admin));
        for (uint256 i = 0; i < operators.length; i++) {
            assert(amm.hasRole(amm.OPERATOR_ROLE(), operators[i]));
        }
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            assert(amm.hasRole(amm.EMERGENCY_ROLE(), emergencyAdmins[i]));
        }
    }

    function test_AddLiquidity() public {
        uint256 ethAmount = 1 ether;
        uint256 tokenAmount = 123 ether;

        uint256 previousTokenBalance = token.balanceOf(user2);
        uint256 previousEthBalance = user2.balance;

        vm.startPrank(user2);
        vm.expectEmit(true, true, true, false);
        emit LiquidityAdded(user2, address(token), tokenAmount, ethAmount, 0); // shares will be calculated

        uint256 shares = amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);
        vm.stopPrank();

        IERC20 lpToken = IERC20(amm.getLPTokenAddress(address(token)));

        assertEq(address(amm).balance, ethAmount);
        assertEq(token.balanceOf(address(amm)), tokenAmount);
        assertEq(user2.balance, previousEthBalance - ethAmount);
        assertEq(token.balanceOf(user2), previousTokenBalance - tokenAmount);
        assertEq(shares, lpToken.balanceOf(user2));
    }

    function test_RemoveLiquidity() public {
        uint256 ethAmount = 1 ether;
        uint256 tokenAmount = 123 ether;

        vm.startPrank(user2);
        uint256 shares = amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);

        IERC20 lpToken = IERC20(amm.getLPTokenAddress(address(token)));

        // Remove all liquidity
        amm.removeLiquidity(
            address(token),
            shares,
            0, // minEthOut
            0, // minTokensOut
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Verify balances after removal
        uint256 adjustedEthBalance = ethAmount * amm.MINIMUM_LIQUIDITY() / (shares + amm.MINIMUM_LIQUIDITY());
        uint256 adjustedTokenBalance = tokenAmount * amm.MINIMUM_LIQUIDITY() / (shares + amm.MINIMUM_LIQUIDITY());

        // Use assertApproxEqAbs for approximate equality with a small delta
        assertApproxEqAbs(
            user2.balance,
            INITIAL_USER_ETH_BALANCE - adjustedEthBalance,
            1000, // delta of 1000 wei, precision loss
            "ETH balance should be approximately equal"
        );

        assertApproxEqAbs(
            token.balanceOf(user2),
            INITIAL_USER_TOKEN_BALANCE - adjustedTokenBalance,
            1000, // delta of 1000 wei, precision loss
            "Token balance should be approximately equal"
        );

        assertEq(lpToken.balanceOf(user2), 0);

        // user1 add and remove liquidity
        vm.startPrank(user1);
        uint256 shares_1 = amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);
        amm.removeLiquidity(address(token), shares_1, 0, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        assertApproxEqAbs(token.balanceOf(user1), INITIAL_USER_TOKEN_BALANCE, 1000);
        assertApproxEqAbs(user1.balance, INITIAL_USER_ETH_BALANCE, 1000);
        assertEq(lpToken.balanceOf(user1), 0);
    }

    function add_Liquidity_user1() internal {
        uint256 ethAmount = 1 ether;
        uint256 tokenAmount = 123 ether;
        vm.startPrank(user1);
        amm.addLiquidity{value: ethAmount}(address(token), tokenAmount);
        vm.stopPrank();
    }

    function test_SwapETHForTokens() public {
        add_Liquidity_user1();
        uint256 swapAmount = 0.01 ether;

        vm.startPrank(user2);
        uint256 balanceBefore = token.balanceOf(user2);

        vm.expectEmit(true, false, true, false);
        emit TokenSwap(address(token), 0, swapAmount); // tokenAmount will be calculated

        amm.swapETHForTokens{value: swapAmount}(
            address(token),
            0, // minTokensOut
            200, // maxSlippage (2%)
            block.timestamp + 1 hours
        );

        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(user2);
        assertGt(balanceAfter, balanceBefore);
        assertEq(user2.balance, INITIAL_USER_ETH_BALANCE - swapAmount);
    }

    function test_SwapTokensForETH() public {
        add_Liquidity_user1();

        uint256 swapTokenAmount = 1 ether;

        vm.startPrank(user2);
        uint256 balanceBefore = user2.balance;
        token.approve(address(amm), swapTokenAmount);

        amm.swapTokensForETH(
            address(token),
            swapTokenAmount,
            0, // minEthOut
            200, // maxSlippage (2%)
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        uint256 balanceAfter = user2.balance;
        assertGt(balanceAfter, balanceBefore);
        assertEq(token.balanceOf(user2), INITIAL_USER_TOKEN_BALANCE - swapTokenAmount);
    }

    function test_EmergencyPause() public {
        vm.startPrank(emergencyAdmins[0]);
        amm.pause();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        amm.addLiquidity{value: 1 ether}(address(token), 1000 ether);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        amm.removeLiquidity(address(token), 1000 ether, 0, 0, block.timestamp + 1 hours);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        amm.swapTokensForETH(address(token), 1000 ether, 0, 200, block.timestamp + 1 hours);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        amm.swapETHForTokens{value: 1 ether}(address(token), 0, 200, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(emergencyAdmins[0]);
        amm.pause();
        vm.stopPrank();

        vm.startPrank(emergencyAdmins[1]);
        amm.unpause();
        vm.stopPrank();

        vm.startPrank(user2);
        amm.addLiquidity{value: 1 ether}(address(token), 1000 ether);
        vm.stopPrank();
    }

    function test_Slippage() public {
        uint256 largeSwapAmount = 0.9 ether; // 90% of pool size
        add_Liquidity_user1();

        vm.startPrank(user2);
        vm.expectRevert();
        amm.swapETHForTokens{value: largeSwapAmount}(
            address(token),
            0,
            100, // 1% max slippage
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_GetSpotPrice() public {
        // Add initial liquidity with 1 ETH : 123 TOKEN ratio
        add_Liquidity_user1();
        uint256 spotPrice = amm.getSpotPrice(address(token));

        // Price should be ethReserve/tokenReserve * PRICE_SCALE
        // 1 ETH : 123 TOKEN means 1e18 : 123e18
        // So price = (1e18 * 1e18) / (123e18) = 1e18/123
        uint256 expectedPrice = uint256(1e18) / 123;
        assertEq(spotPrice, expectedPrice, "Spot price should match liquidity ratio");
    }

    function test_GetSwapInfo() public {
        add_Liquidity_user1();

        uint256 swapAmount = 0.01 ether;
        (uint256 amountOut, uint256 priceImpact) = amm.getSwapInfo(address(token), swapAmount, true);

        assertGt(amountOut, 0);
        assertLt(priceImpact, 200); // Less than 2%
    }

    function test_RevertWhenDeadlineExpired() public {
        vm.startPrank(user2);

        bytes memory expectedError = abi.encodeWithSignature("SimpleAMM__TransactionExpired(uint256,uint256)", 0, 1);
        vm.expectRevert(expectedError);
        amm.swapTokensForETH(
            address(token),
            0.01 ether,
            0,
            200,
            block.timestamp - 1 // Expired deadline
        );
        vm.stopPrank();
    }

    function test_GetVersion() public view {
        assertEq(amm.getVersion(), "2.0.0");
    }

    function test_SupportMultipleTokens() public {
        add_Liquidity_user1();
        MockERC20 token2 = new MockERC20();
        token2.mint(user2, 1000 ether);

        vm.startPrank(user2);
        token2.approve(address(amm), 1000 ether);
        amm.addLiquidity{value: 1 ether}(address(token2), 100 ether);
        vm.stopPrank();

        assertNotEq(amm.getLPToken(address(token2)), address(0));
        assertNotEq(amm.getLPToken(address(token)), address(0));
        assertNotEq(amm.getLPToken(address(token2)), amm.getLPToken(address(token)));
    }

    function test_EmergencyWithdrawal() public {
        // Setup initial liquidity
        add_Liquidity_user1();

        // Pause the contract first (required for emergency withdrawal)
        vm.prank(emergencyAdmins[0]);
        amm.pause();

        // Record initial balances
        address recipient = makeAddr("recipient");
        uint256 initialEthBalance = recipient.balance;
        uint256 initialTokenBalance = token.balanceOf(recipient);
        uint256 ethPreviousBalance = address(amm).balance;
        uint256 tokenPreviousBalance = token.balanceOf(address(amm));

        uint256 ethWithdrawalAmount = 0.5 ether;
        uint256 tokenWithdrawalAmount = 50 ether;

        // Create withdrawal proposal for both ETH and tokens
        vm.startPrank(emergencyAdmins[0]);
        bytes32 ethProposalId = emergencyMultiSig.proposeWithdrawal(address(0), recipient, ethWithdrawalAmount);
        bytes32 tokenProposalId = emergencyMultiSig.proposeWithdrawal(address(token), recipient, tokenWithdrawalAmount);
        vm.stopPrank();

        // Second signer approves both proposals
        vm.startPrank(emergencyAdmins[1]);
        emergencyMultiSig.approveWithdrawal(ethProposalId);
        emergencyMultiSig.approveWithdrawal(tokenProposalId);
        vm.stopPrank();

        // Execute withdrawals
        vm.startPrank(admin);
        emergencyMultiSig.executeWithdrawal(ethProposalId);
        emergencyMultiSig.executeWithdrawal(tokenProposalId);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(recipient.balance, initialEthBalance + ethWithdrawalAmount, "ETH withdrawal failed");
        assertEq(token.balanceOf(recipient), initialTokenBalance + tokenWithdrawalAmount, "Token withdrawal failed");

        uint256 ethBalance = address(amm).balance;
        uint256 tokenBalance = token.balanceOf(address(amm));
        // Verify contract balances
        assertEq(ethBalance, ethPreviousBalance - ethWithdrawalAmount, "Contract ETH balance incorrect");
        assertEq(tokenBalance, tokenPreviousBalance - tokenWithdrawalAmount, "Contract token balance incorrect");
    }

    function test_RevertIf_EmergencyWithdrawal_NotEnoughApprovals() public {
        // Setup initial liquidity
        add_Liquidity_user1();

        uint256 ethWithdrawalAmount = 0.5 ether;
        address recipient = makeAddr("recipient");

        // Pause the contract first (required for emergency withdrawal)
        vm.prank(emergencyAdmins[0]);
        amm.pause();

        // Create withdrawal proposal for both ETH and tokens
        vm.startPrank(emergencyAdmins[0]);
        bytes32 ethProposalId = emergencyMultiSig.proposeWithdrawal(address(0), recipient, ethWithdrawalAmount);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("EmergencyMultiSig__InsufficientApprovals()"));
        emergencyMultiSig.executeWithdrawal(ethProposalId);
        vm.stopPrank();
    }
}
