// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/DexCore.sol";

contract DexCoreTest is Test {
    DexCore public core;

    function setUp() public {
        core = new DexCore();
    }

    function testAddLiquidity() public {
        
    }

    function testSwapping(uint256 x) public {
    }
}
