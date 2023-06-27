// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./DexPool.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

//TBD: use create2

contract DexManager {
    mapping(uint256 => address) public pools;
    uint256 public fee;

    constructor(uint256 _fee) {
        //set initial values, eg. the fees
        fee = _fee;
    }

    /// @notice deploy pool to a deterministic address, based on the token addresses
    /// this way, we will know if a particular pair is pre-existing
    function startPool(address token0, address token1, string memory lpName, string memory lpSymbol)
        external
        returns (address newPoolAddress)
    {
        //start a pool, or return existing pool
        uint256 poolKey = uint256(keccak256(abi.encodePacked(address(token0), address(token1))));
        newPoolAddress = pools[poolKey];

        if (newPoolAddress == address(0)) {
            DexPool pool = new DexPool(token0, token1, lpName, lpSymbol);
            pools[poolKey] = address(pool);
            newPoolAddress = address(pool);
        }
    }
}
