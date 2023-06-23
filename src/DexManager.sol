// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract DexManager {

    constructor() {
        //set initial values, eg. the fees
    }

    function startPool(IERC20 token0, IERC20 token1) external returns (address) {
        //start a pool, or return existing pool
        return address(0);
    }


}
