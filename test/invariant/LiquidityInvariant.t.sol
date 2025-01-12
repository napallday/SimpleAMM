// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMMV2Handler} from "./SimpleAMMV2Handler.t.sol";
import {LPToken} from "../../src/LPToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SimpleAMMV2} from "../../src/v2/SimpleAMMV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract LiquidityInvariantTest is Test {
    SimpleAMMV2Handler public handler;
    uint256 public initialRatio;
    uint256 public constant PRECISION = 1e18;
    SimpleAMMV2 public amm;
    MockERC20 public token;
    address public user;

    function setUp() public {
        handler = new SimpleAMMV2Handler();
        amm = handler.amm();
        token = handler.token();
        user = handler.user();

        // calculate initial ratio
        (uint256 tokenReserve, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        initialRatio = (ethReserve * PRECISION) / tokenReserve;

        // Only target liquidity functions
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.addLiquidity.selector;
        selectors[1] = handler.removeLiquidity.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_ReserveRatio() public view {
        (uint256 tokenReserve, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        if (tokenReserve == 0 || ethReserve == 0) return;

        // Calculate current ratio (scaled by PRECISION: 1e18)
        uint256 currentRatio = (ethReserve * PRECISION) / tokenReserve;

        // Allow for small rounding errors (0.1% tolerance)
        assertApproxEqRel(
            currentRatio,
            initialRatio,
            1e15, // 0.1% tolerance
            "ETH/Token ratio should remain constant"
        );
    }

    function invariant_LiquidityRatios() public view {
        address lpTokenAddr = amm.getLPTokenAddress(address(token));
        assert(lpTokenAddr != address(0));

        LPToken lpToken = LPToken(lpTokenAddr);
        uint256 totalSupply = lpToken.totalSupply();

        (uint256 tokenReserve, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        if (tokenReserve == 0 || ethReserve == 0) return;

        uint256 sqrtK = Math.sqrt(tokenReserve * ethReserve);
        assertApproxEqRel(
            totalSupply,
            sqrtK,
            1e15, // 0.1% tolerance
            "Total supply should match geometric mean of reserves"
        );
    }

    function invariant_MinimumLiquidity() public view {
        address lpTokenAddr = amm.getLPTokenAddress(address(token));
        assert(lpTokenAddr != address(0));

        LPToken lpToken = LPToken(lpTokenAddr);
        assertEq(lpToken.balanceOf(address(1)), amm.MINIMUM_LIQUIDITY(), "Minimum liquidity should always be locked");
    }

    function invariant_ReservesNotZero() public view {
        (uint256 tokenReserve, uint256 ethReserve,) = amm.getPoolInfo(address(token));
        assertGt(tokenReserve, 0, "Token reserve should never be zero");
        assertGt(ethReserve, 0, "ETH reserve should never be zero");
    }
}
