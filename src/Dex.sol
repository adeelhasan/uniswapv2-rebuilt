// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./DexPool.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

//TBD: use create2
//TBD: how will we list all pools, need a convenient way

contract Dex {
    mapping(uint256 => address) public pools;
    uint256 public fee;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    /// @notice deploy pool to a deterministic address, based on the token addresses
    function startPool(address token0, address token1, string memory lpName, string memory lpSymbol)
        external
        returns (address newPoolAddress)
    {
        require(token0 != address(0) && token1 != address(0), "tokens cannot be address(0)");
        require(token0 != token1, "tokens cannot be the same");
        //start a pool, or return existing pool
        uint256 poolKey;
        if (token0 > token1)
            poolKey = uint256(keccak256(abi.encodePacked(address(token0), address(token1))));
        else
            poolKey = uint256(keccak256(abi.encodePacked(address(token1), address(token0))));

        newPoolAddress = pools[poolKey];

        if (newPoolAddress == address(0)) {
            DexPool pool = new DexPool(token0, token1, lpName, lpSymbol);
            pools[poolKey] = address(pool);
            newPoolAddress = address(pool);
        }
    }

    function getPool(address token0, address token1) external view returns (address poolAddress) {
        uint256 poolKey;
        if (token0 > token1)
            poolKey = uint256(keccak256(abi.encodePacked(address(token0), address(token1))));
        else
            poolKey = uint256(keccak256(abi.encodePacked(address(token1), address(token0))));

        poolAddress = pools[poolKey];
    }
}
