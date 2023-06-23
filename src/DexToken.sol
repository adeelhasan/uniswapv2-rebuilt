// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";

contract DexToken is ERC4626 {

    constructor(address underlying) ERC20("ERC4626Mock", "E4626M") ERC4626(IERC20(underlying)) {}

    // when deposit is received, do we mint shares?
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    // when deposit is returned, we burn the shares ... and asset + interest (if any) should go back
    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
