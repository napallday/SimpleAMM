// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LPToken
 * @notice ERC20 token representing liquidity provider shares in AMM pools
 * @dev Extends OpenZeppelin's ERC20 and Ownable contracts
 */
contract LPToken is ERC20, Ownable {
    /// @notice Creates a new LP token with specified name and symbol
    /// @param tokenName Name of the LP token
    /// @param tokenSymbol Symbol of the LP token
    /// @dev Sets msg.sender as owner through Ownable constructor
    constructor(string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) Ownable(msg.sender) {}

    /// @notice Mints new LP tokens to specified address
    /// @param to Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    /// @dev Can only be called by owner (AMM contract)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burns LP tokens from specified address
    /// @param from Address to burn tokens from
    /// @param amount Amount of tokens to burn
    /// @dev Can only be called by owner (AMM contract)
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
