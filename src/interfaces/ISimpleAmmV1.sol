// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISimpleAMMV1 {
    /*//////////////////////////////////////////////////////////////
                              ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                              LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function addLiquidity(address tokenAddress, uint256 tokenAmount) external payable returns (uint256);
    function removeLiquidity(
        address tokenAddress,
        uint256 shares,
        uint256 minEthOut,
        uint256 minTokensOut,
        uint256 deadline
    ) external;

    /*//////////////////////////////////////////////////////////////
                              SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function swapETHForTokens(address tokenAddress, uint256 minTokensOut, uint256 maxSlippage, uint256 deadline)
        external
        payable;

    function swapTokensForETH(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 minEthOut,
        uint256 maxSlippage,
        uint256 deadline
    ) external;

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getPoolInfo(address tokenAddress)
        external
        view
        returns (uint256 ethReserve, uint256 tokenReserve, uint256 totalShares);

    function getLPToken(address tokenAddress) external view returns (address);

    function getSpotPrice(address tokenAddress) external view returns (uint256);

    function getSwapInfo(address tokenAddress, uint256 amountIn, bool isEthIn)
        external
        view
        returns (uint256 amountOut, uint256 priceImpact);

    function getLiquidityDepth(address tokenAddress) external view returns (uint256);

    function getVersion() external pure returns (string memory);
}
