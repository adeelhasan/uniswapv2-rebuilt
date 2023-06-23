// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/DexManager.sol";

contract DexManagerTest is Test {
    DexCore public core;

    function setUp() public {
        core = new DexCore();
    }

    function testAddLiquidity() public {
        
    }

    function testSwapping(uint256 x) public {
    }
}
