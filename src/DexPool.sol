// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "./DexToken.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import { UD60x18, ud } from "prb-math/UD60x18.sol";

//import safetransfer
//is the fee kept here, or in the main dex contract
//is the fee always in TokenA terms? 
//fee comes out from the amount being swapped -- which is reduced
//for a pair A, B -- is the swap always from A to B? what about from B to A? should be both ways
//or can both happen at the same time?

contract DexPool is ERC4626 {

    UD60x18 private _reserve0;
    UD60x18 private _reserve1;
    address public immutable token0;
    address public immutable token1;
    address public immutable dex;

    /// only a dex pool manager should be able to start a pool
    /// the only way to restrict is really to see the address and compare to a hardcoded one
    constructor(address _token0, address _token1, string memory lpName, string memory lpSymbol) ERC4626(IERC20(_token0)) ERC20(lpName, lpSymbol) {
        //require((amount0 > 0) && (amount1 > 0), "cannot create an empty pool");
        token0 = _token0;
        token1 = _token1;
        dex = msg.sender;

        //string memory liquidityTokenName = string.concat(_token0.name(), _token1.name());
        //string memory liquidityTokenString = string.concat(_token0.symbol(), _token1.symbol());
        //liquidityToken = new DexPoolLiquidityToken(_token0, liquidityTokenName, liquidityTokenString);

        

        //transfer ... can the other internal function be called as well?
    }

    /// @notice add liquidity by depositing tokens in prevailing ratio
    /// @dev these tokens should have been approved for allowance in the amounts    
    function depositPair(uint256 amount0, uint256 amount1) external {
        //check approval
        require(amount0 <= IERC20(token0).allowance(msg.sender, address(this)), "insufficient allowance for 0");
        require(amount1 <= IERC20(token1).allowance(msg.sender, address(this)), "insufficient allowance for 1");

        /// TBD
        /// check if ratio is preserved
        /// the ratio is a "at least as existing ratio"
        //  if extra tokens are sent, they get into the contract's balance
        //  but corresponding lp tokens are rounded off
        _checkConstantRatio(ud(amount0), ud(amount1));

        //transfer to self
        IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1);

        //issue liquidity tokens from the ERC4626
        UD60x18 lpQuantity = _calculateLiquidity(amount0, amount1);
        //console.log(lpQuantity.intoUint256());
        _mint(msg.sender, lpQuantity.intoUint256());

        //_reserve0.add()

        //update reserves
        
    }

    /// @notice this will burn shares and then transfer assets (tokenA & tokenB) back
    /// @dev the calculation is done as a percentage of what the lp tokens are
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        UD60x18 percentageOwnership = ud(shares).div(ud(totalSupply()));

        //this will burn the lp tokens
        super.redeem(shares, address(this), msg.sender);

        _reserve0 = ud(IERC20(token0).balanceOf(address(this)));
        _reserve1 = ud(IERC20(token1).balanceOf(address(this)));

        uint256 token0Return = _reserve0.mul(percentageOwnership).intoUint256();
        uint256 token1Return = _reserve1.mul(percentageOwnership).intoUint256();

        IERC20(token0).transfer(msg.sender, token0Return);
        IERC20(token1).transfer(msg.sender, token1Return);
    }

    function _convertToAssets(uint256 shares, Math.Rounding) internal view override returns (uint256) {
        return 0;
    }

    function previewDeposit(uint256 amount0, uint256 amount1) external pure returns (uint256) {
        return _calculateLiquidity(amount0, amount1).intoUint256();
    }

    function _checkConstantRatio(UD60x18 amount0, UD60x18 amount1) internal {
        UD60x18 reserveTokenA = ud(IERC20(token0).balanceOf(address(this)));
        UD60x18 reserveTokenB = ud(IERC20(token1).balanceOf(address(this)));

        if (reserveTokenB.intoUint256() > 0) {
            UD60x18 currentConstant = reserveTokenA.div(reserveTokenB);
            UD60x18 incomingConstant = amount0.div(amount1);

            require(currentConstant == incomingConstant, "ratio of amounts not consistent");
        }

    }

    /// @dev square root of token A amount * token B amount
    function _calculateLiquidity(uint256 amount0, uint256 amount1) internal pure returns (UD60x18 liquidityAmount) {

        liquidityAmount = (ud(amount0).mul(ud(amount1))).sqrt();
    }

    //msg.sender has token0, convert to token1 and return
    //if useToken0 is false, then convert from token1 to token0
    //subject to Fee, we get the Fee from the "Manager" contract
    // transfer the tokens first, and then call swap ...
    function swap(uint256 amount, bool useToken0) external pure {
        
    }

    /// @notice returns the liquidity that will come, as a simulation
    function previewSwap(uint256 token0Amount) external pure returns (uint256 token1Amount) {
        return _calculateSwap(token0Amount);
    }

    /// @notice how much of token1 will we get for a given token0 amount
    /// @dev factors in the protocol fee
    function _calculateSwap(uint256 token0Amount) internal pure returns(uint256) {
        return token0Amount;
    }

}


/*
    //constructor(IERC20 _token0, IERC20 _token1, uint256 amount0, uint256 amount1) ERC4626(_token0.name(), _token1.symbol()) {
        struct TokenInfo {
            string name;
            string symbol;
            IERC20 token;
            uint256 amount;
        }
        
        contract DexPoolLiquidityToken is ERC4626 {
        
            constructor(ERC20 underlying, string memory name, string memory symbol) ERC4626(underlying) ERC20(name, symbol) {
        
            }
        
        }
*/