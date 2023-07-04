// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./DexPool.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract DexPoolFactory {
    mapping(uint256 => address) public poolsMapping;
    address[] public poolsList;
    uint256 public constant MAX_PAGE_SIZE = 100;

    event PoolStarted(address indexed poolAddress, address indexed token0, address indexed token1);

    error ZeroAddressNotAllowed();
    error TokensCannotBeSame();
    error TooManyPoolsInAPage(uint256 pageSizeRequested);

    /// @notice start a new pool, or return the existing one
    /// @dev didnt use deterministic create2 because then the pool initializer wouldnt be
    // able to use ERC4626. It could use the upgradable ERC4626 perhaps, but then that is a different
    // paradigm to support
    function startPool(address token0, address token1, string memory lpName, string memory lpSymbol)
        external
        returns (address newPoolAddress)
    {
        if (token0 == address(0) || token1 == address(0))
            revert ZeroAddressNotAllowed();
        if (token0 == token1)
            revert TokensCannotBeSame();
        newPoolAddress = getPool(token0, token1);

        if (newPoolAddress == address(0)) {
            DexPool pool = new DexPool(token0, token1, lpName, lpSymbol);
            newPoolAddress = address(pool);

            poolsMapping[_getPoolKey(token0, token1)] = newPoolAddress;
            poolsList.push(newPoolAddress);

            emit PoolStarted(newPoolAddress, token0, token1);
        }
    }

    /// @notice return an existing pool for a given token pair
    function getPool(address token0, address token1) public returns (address poolAddress) {
        poolAddress = poolsMapping[_getPoolKey(token0, token1)];
    }

    function _getPoolKey(address token0, address token1) internal pure returns (uint256 poolKey) {
        if (token0 > token1)
            poolKey = uint256(keccak256(abi.encodePacked(address(token0), address(token1))));
        else
            poolKey = uint256(keccak256(abi.encodePacked(address(token1), address(token0))));
    }

    /// @notice list pairs as organized into pages of results, to avoid very large data returns
    function listPools(uint256 pageNo, uint256 pageSize) external view returns(address[] memory list) {
        if (pageSize > MAX_PAGE_SIZE)
            revert TooManyPoolsInAPage(pageSize);
        uint256 poolsCount = poolsList.length;
        uint256 startOffset = (pageNo-1) * pageSize;
        uint256 endOffset = startOffset + pageSize;
        if (endOffset > poolsCount)
            endOffset = poolsCount;
        list = new address[](endOffset - startOffset);
        for (uint i = startOffset; i < endOffset; ) {
            list[i] = poolsList[i];
            unchecked { i++; }
        } 
    }

}
