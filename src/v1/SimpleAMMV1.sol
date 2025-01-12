// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../LPToken.sol";
import "../EmergencyMultiSig.sol";
import "../storage/EternalStorage.sol";
import "../storage/EternalStorageAccessLibrary.sol";
import "../interfaces/ISimpleAmmV1.sol";
import "../interfaces/IMultiSigExecutor.sol";

/// @title SimpleAMMV1 - A Simple Automated Market Maker with ETH/Token Pairs
/// @author napallday
/// @notice Provides basic AMM functionality for swapping between ETH and ERC20 tokens
///         This file is only for demonstrating the migration process, it doesn't have test cases.
///         For the real project, please refer to the SimpleAMMV2.sol file.
/// @dev Uses constant product formula (x*y=k) with a fee mechanism and eternal storage pattern
contract SimpleAMMV1 is ISimpleAMMV1, IMultiSigExecutor, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using EternalStorageAccessLibrary for EternalStorage;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error SimpleAMM__InvalidAmount(uint256 provided, uint256 required);
    error SimpleAMM__ZeroETHAmount();
    error SimpleAMM__PoolNotExist(address token);
    error SimpleAMM__EmptyPool(address token, uint256 ethReserve, uint256 tokenReserve);
    error SimpleAMM__InsufficientLiquidity(uint256 reserveIn, uint256 reserveOut);
    error SimpleAMM__InsufficientInitialLiquidity(uint256 provided, uint256 minimum);
    error SimpleAMM__InsufficientLiquidityMinted(uint256 sharesByEth, uint256 sharesByToken);
    error SimpleAMM__InsufficientLPTokenBalance(uint256 requested, uint256 balance);
    error SimpleAMM__InsufficientOutput(uint256 amountOut, uint256 minRequired);
    error SimpleAMM__SlippageConfigTooHigh(uint256 provided, uint256 maximum);
    error SimpleAMM__PriceImpactTooHigh(uint256 impact, uint256 maxSlippage);
    error SimpleAMM__SwapAmountTooHigh(uint256 amountIn, uint256 maxAllowed);
    error SimpleAMM__TransactionExpired(uint256 deadline, uint256 timestamp);
    error SimpleAMM__ZeroAddress(string parameter);
    error SimpleAMM__InvalidOperatorAddress(address operator);
    error SimpleAMM__InvalidEmergencyAdminAddress(address admin);
    error SimpleAMM__InvalidTokenAddress(address token);
    error SimpleAMM__OnlyMultisigAllowed(address sender);
    error SimpleAMM__AlreadyInitialized();
    error SimpleAMM__MustInitialized();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event LiquidityAdded(
        address indexed provider, address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 shares
    );
    event LiquidityRemoved(
        address indexed provider, address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 shares
    );
    event TokenSwap(address indexed token, uint256 tokenAmount, uint256 ethAmount);
    event FeeUpdated(uint256 oldFee, uint256 newFee);

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/
    // The actual pool struct is stored in the eternal storage
    // struct Pool {
    //     uint256 tokenReserve;
    //     uint256 ethReserve;
    //     LPToken lpToken;
    // }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////*/
    string public constant VERSION = "1.0.0";

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    uint256 public constant MINIMUM_LIQUIDITY = 1_000_000;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant FEE = 30; // 0.3% fee
    uint256 public constant MAX_SLIPPAGE = 2000; // 20%
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;
    uint256 public constant MAX_TRADE_SIZE_BPS = 5000; // 50%
    uint256 public constant PRICE_SCALE = 1e18;

    // use eternal storage for fee, emergency multisig, and pools
    EternalStorage public immutable store;
    // don't need to store in EternalStorage
    bool private initialized;

    // // Mutable state variables
    // uint256 public fee = 30; // Initial fee 0.3%
    // mapping(address => Pool) public pools;
    // EmergencyMultiSig public emergencyMultiSig;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier notExpire(uint256 deadline) {
        if (block.timestamp > deadline) revert SimpleAMM__TransactionExpired(deadline, block.timestamp);
        _;
    }

    modifier initializer() {
        if (initialized) revert SimpleAMM__AlreadyInitialized();
        _;
        initialized = true;
    }

    modifier mustInitialized() {
        if (!initialized) revert SimpleAMM__MustInitialized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address admin, address[] memory operators, address[] memory emergencyAdmins, address _store) {
        if (admin == address(0)) revert SimpleAMM__ZeroAddress("admin");
        if (_store == address(0)) revert SimpleAMM__ZeroAddress("store");

        store = EternalStorage(_store);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // Set up operators
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] == address(0)) revert SimpleAMM__InvalidOperatorAddress(operators[i]);
            _grantRole(OPERATOR_ROLE, operators[i]);
        }

        // Set up emergency admins
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyAdmins[i] == address(0)) revert SimpleAMM__InvalidEmergencyAdminAddress(emergencyAdmins[i]);
            _grantRole(EMERGENCY_ROLE, emergencyAdmins[i]);
        }
    }

    /// @notice Initializes the AMM with emergency multisig address and initial fee
    /// @param _emergencyMultiSig Address of the emergency multisig contract
    /// @dev Can only be called once by admin after contract deployment
    function initialize(address _emergencyMultiSig) external initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_emergencyMultiSig == address(0)) revert SimpleAMM__ZeroAddress("multisig");
        store.setEmergencyMultiSig(_emergencyMultiSig);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Pauses all contract operations in case of emergency
    /// @dev Can only be called by accounts with EMERGENCY_ROLE
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    /// @notice Unpauses contract operations
    /// @dev Can only be called by accounts with EMERGENCY_ROLE
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    /// @notice Allows emergency withdrawal of tokens/ETH when contract is paused
    /// @param token Address of token to withdraw (address(0) for ETH)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    /// @dev Can only be called through emergency multisig when contract is paused
    function executeEmergencyWithdraw(address token, address to, uint256 amount) external whenPaused {
        if (msg.sender != store.getEmergencyMultiSig()) revert SimpleAMM__OnlyMultisigAllowed(msg.sender);

        if (token == address(0)) {
            // Withdraw ETH
            payable(to).sendValue(amount);
        } else {
            // Withdraw ERC20 tokens
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VERSION
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the contract version
    /// @return Version string
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDITY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to a token-ETH pool
    /// @param tokenAddress The ERC20 token address for the pool
    /// @param tokenAmount The amount of tokens to add
    /// @return shares The amount of LP tokens minted
    /// @dev Creates new pool if doesn't exist, otherwise adds to existing pool
    /// @dev First deposit mints MINIMUM_LIQUIDITY to address(1) to prevent inflation attack
    /// @dev Subsequent deposits maintain price ratio by adjusting deposit amounts
    function addLiquidity(address tokenAddress, uint256 tokenAmount)
        external
        payable
        nonReentrant
        whenNotPaused
        mustInitialized
        returns (uint256 shares)
    {
        if (tokenAddress == address(0)) revert SimpleAMM__InvalidTokenAddress(tokenAddress);
        if (tokenAmount == 0) revert SimpleAMM__InvalidAmount(tokenAmount, 1);
        if (msg.value == 0) revert SimpleAMM__InvalidAmount(msg.value, 1);

        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);

        uint256 ethAmount = msg.value;
        if (lpTokenAddr == address(0)) {
            lpTokenAddr = _createNewPool(tokenAddress);
        } else {
            // Calculate token amount based on current ratio
            uint256 tokensAmountBasedOnEth = (msg.value * tokenReserve) / ethReserve;

            // Use the smaller ratio to maintain price
            if (tokensAmountBasedOnEth <= tokenAmount) {
                // ETH is the limiting factor
                tokenAmount = tokensAmountBasedOnEth;
            } else {
                uint256 ethAmountBasedOnTokens = (tokenAmount * ethReserve) / tokenReserve;
                // Token is the limiting factor
                ethAmount = ethAmountBasedOnTokens;
            }
        }

        LPToken lpToken = LPToken(lpTokenAddr);
        uint256 totalSupply = lpToken.totalSupply();

        shares = _calculateLiquidityShares(tokenAmount, ethAmount, tokenReserve, ethReserve, lpTokenAddr);

        // Effects
        store.setPoolTokenReservesWithAddress(tokenAddress, tokenReserve + tokenAmount);
        store.setPoolEthReservesWithAddress(tokenAddress, ethReserve + ethAmount);

        // Interactions
        if (totalSupply == 0) {
            // mint MINIMUM_LIQUIDITY to the address(1) to avoid vault inflation attack
            lpToken.mint(address(1), MINIMUM_LIQUIDITY);
        }
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);
        lpToken.mint(msg.sender, shares);
        // Refund excess ETH
        if (ethAmount < msg.value) {
            payable(msg.sender).sendValue(msg.value - ethAmount);
        }

        emit LiquidityAdded(msg.sender, tokenAddress, tokenAmount, ethAmount, shares);
    }

    /// @notice Removes liquidity from a token-ETH pool
    /// @param tokenAddress The ERC20 token address of the pool
    /// @param shares Amount of LP tokens to burn
    /// @param minEthOut Minimum ETH to receive
    /// @param minTokensOut Minimum tokens to receive
    /// @param deadline Transaction deadline timestamp
    /// @dev Burns LP tokens and returns proportional amount of pool assets
    function removeLiquidity(
        address tokenAddress,
        uint256 shares,
        uint256 minEthOut,
        uint256 minTokensOut,
        uint256 deadline
    ) external nonReentrant whenNotPaused notExpire(deadline) mustInitialized {
        if (shares == 0) revert SimpleAMM__InvalidAmount(shares, 1);

        (uint256 ethAmount, uint256 tokenAmount, LPToken lpToken) =
            _calculateRemoveLiquidityAmounts(tokenAddress, shares, minEthOut, minTokensOut);

        _updateReservesForRemoveLiquidity(tokenAddress, tokenAmount, ethAmount);

        lpToken.burn(msg.sender, shares);
        payable(msg.sender).sendValue(ethAmount);
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);

        emit LiquidityRemoved(msg.sender, tokenAddress, tokenAmount, ethAmount, shares);
    }

    /*//////////////////////////////////////////////////////////////
                               SWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Swaps ETH for tokens
    /// @param tokenAddress The ERC20 token address to receive
    /// @param minTokensOut Minimum tokens to receive
    /// @param maxSlippage Maximum allowed price impact in basis points
    /// @param deadline Transaction deadline timestamp
    /// @dev Uses constant product formula with fee adjustment
    function swapETHForTokens(address tokenAddress, uint256 minTokensOut, uint256 maxSlippage, uint256 deadline)
        external
        payable
        nonReentrant
        whenNotPaused
        notExpire(deadline)
        mustInitialized
    {
        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);
        if (maxSlippage > MAX_SLIPPAGE) revert SimpleAMM__SlippageConfigTooHigh(maxSlippage, MAX_SLIPPAGE);
        if (msg.value == 0) revert SimpleAMM__ZeroETHAmount();

        uint256 tokensBought = _getAmountOut(msg.value, ethReserve, tokenReserve);
        if (tokensBought < minTokensOut) revert SimpleAMM__InsufficientOutput(tokensBought, minTokensOut);

        uint256 priceImpact = _calculatePriceImpact(msg.value, tokensBought, ethReserve, tokenReserve);
        if (priceImpact > maxSlippage) revert SimpleAMM__PriceImpactTooHigh(priceImpact, maxSlippage);

        // Effects before interactions (CEI pattern)
        store.setPoolTokenReservesWithAddress(tokenAddress, tokenReserve - tokensBought);
        store.setPoolEthReservesWithAddress(tokenAddress, ethReserve + msg.value);

        // Move event emission before external call
        emit TokenSwap(tokenAddress, tokensBought, msg.value);

        // External call last
        IERC20(tokenAddress).safeTransfer(msg.sender, tokensBought);
    }

    /// @notice Swaps tokens for ETH
    /// @param tokenAddress The ERC20 token address to swap
    /// @param tokenAmount Amount of tokens to swap
    /// @param minEthOut Minimum ETH to receive
    /// @param maxSlippage Maximum allowed price impact in basis points
    /// @param deadline Transaction deadline timestamp
    /// @dev Uses constant product formula with fee adjustment
    function swapTokensForETH(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 minEthOut,
        uint256 maxSlippage,
        uint256 deadline
    ) external nonReentrant whenNotPaused notExpire(deadline) mustInitialized {
        // Checks
        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);
        if (maxSlippage > MAX_SLIPPAGE) revert SimpleAMM__SlippageConfigTooHigh(maxSlippage, MAX_SLIPPAGE);

        uint256 ethBought = _getAmountOut(tokenAmount, tokenReserve, ethReserve);
        if (ethBought < minEthOut) revert SimpleAMM__InsufficientOutput(ethBought, minEthOut);

        uint256 priceImpact = _calculatePriceImpact(tokenAmount, ethBought, tokenReserve, ethReserve);
        if (priceImpact > maxSlippage) revert SimpleAMM__PriceImpactTooHigh(priceImpact, maxSlippage);

        // Effects before interactions
        store.setPoolTokenReservesWithAddress(tokenAddress, tokenReserve + tokenAmount);
        store.setPoolEthReservesWithAddress(tokenAddress, ethReserve - ethBought);

        // External calls last - pull before push pattern
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Move event emission before ETH transfer
        emit TokenSwap(tokenAddress, tokenAmount, ethBought);

        payable(msg.sender).sendValue(ethBought);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets pool information for a token-ETH pair
    /// @param tokenAddress The ERC20 token address
    /// @return tokenReserve Current token reserve in pool
    /// @return ethReserve Current ETH reserve in pool
    /// @return totalShares Total LP tokens issued
    function getPoolInfo(address tokenAddress)
        external
        view
        returns (uint256 tokenReserve, uint256 ethReserve, uint256 totalShares)
    {
        address lpTokenAddr;
        (tokenReserve, ethReserve, lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);
        totalShares = LPToken(lpTokenAddr).totalSupply();
    }

    /// @notice Gets LP token address for a token-ETH pair
    /// @param tokenAddress The ERC20 token address
    /// @return Address of the LP token contract
    function getLPToken(address tokenAddress) external view returns (address) {
        if (tokenAddress == address(0)) revert SimpleAMM__InvalidTokenAddress(tokenAddress);
        return store.getPoolLPTokenWithAddress(tokenAddress);
    }

    /// @notice Gets current spot price of token in terms of ETH
    /// @param tokenAddress The ERC20 token address
    /// @return Spot price scaled by PRICE_SCALE
    function getSpotPrice(address tokenAddress) external view returns (uint256) {
        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);
        if (ethReserve == 0 || tokenReserve == 0) {
            revert SimpleAMM__EmptyPool(tokenAddress, ethReserve, tokenReserve);
        }

        // price = ethReserve/tokenReserve * PRICE_SCALE
        return (ethReserve * PRICE_SCALE) / tokenReserve;
    }

    /// @notice Gets swap output amount and price impact
    /// @param tokenAddress The ERC20 token address
    /// @param amountIn Input amount
    /// @param isEthIn True if input is ETH, false if input is token
    /// @return amountOut Expected output amount
    /// @return priceImpact Expected price impact in basis points
    function getSwapInfo(address tokenAddress, uint256 amountIn, bool isEthIn)
        external
        view
        returns (uint256 amountOut, uint256 priceImpact)
    {
        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);

        if (isEthIn) {
            amountOut = _getAmountOut(amountIn, ethReserve, tokenReserve);
            priceImpact = _calculatePriceImpact(amountIn, amountOut, ethReserve, tokenReserve);
        } else {
            amountOut = _getAmountOut(amountIn, tokenReserve, ethReserve);
            priceImpact = _calculatePriceImpact(amountIn, amountOut, tokenReserve, ethReserve);
        }
    }

    /// @notice Gets liquidity depth (geometric mean of reserves)
    /// @param tokenAddress The ERC20 token address
    /// @return Square root of token reserve * ETH reserve
    function getLiquidityDepth(address tokenAddress) external view returns (uint256) {
        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);

        return Math.sqrt(ethReserve * tokenReserve);
    }

    /// @notice Gets LP token contract address
    /// @param tokenAddress The ERC20 token address
    /// @return Address of LP token contract
    function getLPTokenAddress(address tokenAddress) external view returns (address) {
        return store.getPoolLPTokenWithAddress(tokenAddress);
    }

    /// @notice Gets current trading fee
    /// @return Fee in basis points (1 = 0.01%)
    function getFee() external pure returns (uint256) {
        return FEE;
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _calculateLiquidityShares(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 tokenReserve,
        uint256 ethReserve,
        address lpTokenAddr
    ) private view returns (uint256 shares) {
        LPToken lpToken = LPToken(lpTokenAddr);
        uint256 totalSupply = lpToken.totalSupply();

        if (totalSupply == 0) {
            shares = Math.sqrt(ethAmount * tokenAmount);
            if (shares < MINIMUM_LIQUIDITY) {
                revert SimpleAMM__InsufficientInitialLiquidity(shares, MINIMUM_LIQUIDITY);
            }
            shares -= MINIMUM_LIQUIDITY;
        } else {
            uint256 sharesByEth = (ethAmount * totalSupply) / ethReserve;
            uint256 sharesByToken = (tokenAmount * totalSupply) / tokenReserve;
            shares = Math.min(sharesByEth, sharesByToken);
            if (shares == 0) {
                revert SimpleAMM__InsufficientLiquidityMinted(sharesByEth, sharesByToken);
            }
        }
        return shares;
    }

    function _calculatePriceImpact(uint256 amountIn, uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        if (reserveIn == 0 || reserveOut == 0) revert SimpleAMM__InsufficientLiquidity(reserveIn, reserveOut);
        if (amountIn == 0) revert SimpleAMM__InvalidAmount(amountIn, 1);
        if (amountIn > reserveIn * MAX_TRADE_SIZE_BPS / 10000) {
            revert SimpleAMM__SwapAmountTooHigh(amountIn, reserveIn * MAX_TRADE_SIZE_BPS / 10000);
        }

        // Calculate price impact using actual amounts
        uint256 spotPrice = (reserveOut * SLIPPAGE_DENOMINATOR) / reserveIn;
        uint256 actualPrice = (amountOut * SLIPPAGE_DENOMINATOR) / amountIn;

        if (actualPrice >= spotPrice) return 0;

        return ((spotPrice - actualPrice) * SLIPPAGE_DENOMINATOR) / spotPrice;
    }

    function _calculateRemoveLiquidityAmounts(
        address tokenAddress,
        uint256 shares,
        uint256 minEthOut,
        uint256 minTokensOut
    ) private view returns (uint256 ethAmount, uint256 tokenAmount, LPToken lpToken) {
        (uint256 tokenReserve, uint256 ethReserve, address lpTokenAddr) = store.getPoolWithAddress(tokenAddress);
        if (lpTokenAddr == address(0)) revert SimpleAMM__PoolNotExist(tokenAddress);

        lpToken = LPToken(lpTokenAddr);
        uint256 totalSupply = lpToken.totalSupply();
        uint256 balance = lpToken.balanceOf(msg.sender);
        if (shares > balance) revert SimpleAMM__InsufficientLPTokenBalance(shares, balance);

        ethAmount = (shares * ethReserve) / totalSupply;
        tokenAmount = (shares * tokenReserve) / totalSupply;

        if (ethAmount < minEthOut) revert SimpleAMM__InsufficientOutput(ethAmount, minEthOut);
        if (tokenAmount < minTokensOut) revert SimpleAMM__InsufficientOutput(tokenAmount, minTokensOut);

        return (ethAmount, tokenAmount, lpToken);
    }

    function _updateReservesForRemoveLiquidity(address tokenAddress, uint256 tokenAmount, uint256 ethAmount) private {
        (uint256 tokenReserve, uint256 ethReserve,) = store.getPoolWithAddress(tokenAddress);
        store.setPoolTokenReservesWithAddress(tokenAddress, tokenReserve - tokenAmount);
        store.setPoolEthReservesWithAddress(tokenAddress, ethReserve - ethAmount);
    }

    function _createNewPool(address tokenAddress) private returns (address) {
        string memory tokenSymbol = IERC20Metadata(tokenAddress).symbol();
        string memory lpName = string.concat(tokenSymbol, "-ETH LP Token");
        string memory lpSymbol = string.concat(tokenSymbol, "-ETH-LP");

        LPToken lpToken = new LPToken(lpName, lpSymbol);
        address lpTokenAddr = address(lpToken);
        store.setPoolLPTokenWithAddress(tokenAddress, lpTokenAddr);
        return lpTokenAddr;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) private view returns (uint256) {
        if (amountIn == 0) revert SimpleAMM__InvalidAmount(amountIn, 1);
        if (reserveIn == 0 || reserveOut == 0) {
            revert SimpleAMM__InsufficientLiquidity(reserveIn, reserveOut);
        }

        // dx(1-f) = amountIn * (1 - FEE/FEE_DENOMINATOR)
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - store.getFee());
        // numerator = dx(1-f)y0
        uint256 numerator = amountInWithFee * reserveOut;
        // denominator = x0 * FEE_DENOMINATOR + dx(1-f)
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;

        // dy = [dx(1-f)y0] / [x0 + dx(1-f)]
        return numerator / denominator;
    }
}
