// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./DexToken.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
//import safetransfer

contract DexPool is ERC4626 {

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    /// question: should these be IERC20 typecast?
    /// question: can we set the decimal point here, for the vault token
    constructor(IERC20 _token0, IERC20 _token1, uint256 amount0, uint256 amount1) {
        require((amount0 > 0) && (amount1 > 0), "cannot create an empty pool");
        token0 = _token0;
        token1 = _token1;
    }

    /// these tokens should have been approved for allowance in the amounts
    function deposit( uint256 amount0, uint256 amount1) external pure {
        //check approval
        //transfer to self
        //issue liquidity tokens from the ERC4626
    }

    /// @dev square root of token A amount * token B amount
    function calculateLiquidity() external pure returns (uint256) {

    }

    //msg.sender has token0, convert to token1 and return
    //if useToken0 is false, then convert from token1 to token0
    //subject to Fee, we get the Fee from the "Manager" contract
    function swap(uint256 amount, bool useToken0) external pure {
        
    }

    function previewSwap(uint256 amount, bool useToken0) external pure {
    }

    /// @notice how much of a token will we get
    /// @dev factors in the fee
    function calculateSwap(uint256 amount, bool useToken0) internal pure returns(uint256) {
        return 0;
    }





}
