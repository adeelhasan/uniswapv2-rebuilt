// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashLender.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {UD60x18, ud} from "prb-math/UD60x18.sol";
//import "solmate/utils/SafeTransferLib.sol";

//TBD: reflect state changes in events
//Q: how is the data supported ... important in the flash loan as well
//TBD: support for sending in more when depositing, the penalty
//TBD: how to address concerns of front running

contract DexPool is ERC4626, IERC3156FlashLender, ReentrancyGuard {
    address public immutable token0;
    address public immutable token1;
    address public immutable dex;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    UD60x18 private _reserve0;
    UD60x18 private _reserve1;
    UD60x18 private _balances0;
    UD60x18 private _balances1;

    event AssetsDeposited(address indexed from, uint256 liquidityIssued, uint256 amount0, uint256 amount1);
    event Swapped(address indexed token, uint256 amount);
    event Redeemed(address indexed to, uint256 liquidityReturned, uint256 amount0, uint256 amount1);
    event FlashLoanIssued(address indexed borrower, uint256 amount);
    event FlashLoanReturned(address indexed borrower, address indexed token, uint256 amount);

    error InsufficientAllowance(bool token0);
    error NotPoolToken();
    error ZeroAddressNotAllowed();
    error TokensCannotBeSame();
    error FlashLoanAmountTooMuch(uint256 maxLoanAmount);
    error FlashLoanCallbackFailed();
    error FlashLoanTransferToBorroweFailed();
    error SwappedAmountLessThanMinimum(uint256 swappedAmount);

    constructor(address _token0, address _token1, string memory lpName, string memory lpSymbol)
        ERC4626(new ERC20("Placeholder", "PLH"))
        ERC20(lpName, lpSymbol)
    {
        if (_token0 == address(0) || _token1 == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (_token0 == _token1) {
            revert TokensCannotBeSame();
        }
        token0 = _token0;
        token1 = _token1;
        dex = msg.sender;
    }

    /// @notice add liquidity by depositing tokens in prevailing ratio
    /// @dev these tokens should have been approved for allowance in the amounts
    function depositPair(uint256 amount0, uint256 amount1) external {
        //check approval
        if (amount0 > IERC20(token0).allowance(msg.sender, address(this))) {
            revert InsufficientAllowance(true);
        }
        if (amount1 > IERC20(token1).allowance(msg.sender, address(this))) {
            revert InsufficientAllowance(false);
        }

        /// check if ratio is preserved, the ratio is a "at least as existing ratio"
        if (_reserve0.intoUint256() > 0 && _reserve1.intoUint256() > 0)
            _checkConstantRatio(ud(amount0), ud(amount1));

        //transfer to self
        safeTransferFrom(ERC20(token0), msg.sender, address(this), amount0);
        safeTransferFrom(ERC20(token1), msg.sender, address(this), amount1);

        //issue liquidity tokens from the ERC4626
        UD60x18 lpQuantity = _calculateLiquidity(amount0, amount1);

        _mint(msg.sender, lpQuantity.intoUint256());

        //update reserves
        _reserve0 = _reserve0.add(ud(IERC20(token0).balanceOf(address(this))));
        _reserve1 = _reserve1.add(ud(IERC20(token1).balanceOf(address(this))));

        emit AssetsDeposited(msg.sender, lpQuantity.intoUint256(), amount0, amount1);
    }

    /// @notice this will burn shares and then transfer assets (tokenA & tokenB) back
    /// @dev the calculation is done as a percentage of what the lp tokens are
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        UD60x18 percentageOwnership = ud(shares).div(ud(totalSupply()));

        //this will burn the lp tokens
        super.redeem(shares, address(this), msg.sender);

        uint256 token0Return = _reserve0.mul(percentageOwnership).intoUint256();
        uint256 token1Return = _reserve1.mul(percentageOwnership).intoUint256();

        _reserve0 = _reserve0.sub(ud(token0Return));
        _reserve1 = _reserve1.sub(ud(token1Return));

        IERC20(token0).transfer(msg.sender, token0Return);
        IERC20(token1).transfer(msg.sender, token1Return);

        emit Redeemed(receiver, shares, token0Return, token1Return);
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

    /// @notice how many liquidity tokens should be issued for a given deposit
    /// @dev geometric mean, which is square root of token A amount * token B amount
    function _calculateLiquidity(uint256 amount0, uint256 amount1) internal pure returns (UD60x18 liquidityAmount) {
        liquidityAmount = (ud(amount0).mul(ud(amount1))).sqrt();
    }

    /// @dev msg.sender would have approved the amount for transfer
    /// and will be recipient of the swapped token as well
    /// @param amount qty of token coming in
    /// @param useToken0 if useToken0 is true, then token0 is received and token1 given back
    /// and vice versa
    function swap(uint256 amount, bool useToken0, uint256 minSwappedAmount) external {
        UD60x18 swappedAmount = _calculateSwap(amount, useToken0);
        if ((minSwappedAmount > 0) && (swappedAmount < ud(minSwappedAmount)))
            revert SwappedAmountLessThanMinimum(swappedAmount.intoUint256());
        if (useToken0) {
            require(swappedAmount <= _reserve1, "insufficent reserves");
            _reserve0 = _reserve0.add(ud(amount));
            _reserve1 = _reserve1.sub(swappedAmount);

            safeTransferFrom(ERC20(token0), msg.sender, address(this), amount);
            IERC20(token1).transfer(msg.sender, swappedAmount.intoUint256());

            emit Swapped(token0, swappedAmount.intoUint256());
        } else {
            require(swappedAmount <= _reserve0, "insufficent reserves");
            _reserve1 = _reserve1.add(ud(amount));
            _reserve0 = _reserve0.sub(swappedAmount);

            safeTransferFrom(ERC20(token1), msg.sender, address(this), amount);
            IERC20(token1).transfer(msg.sender, swappedAmount.intoUint256());

            emit Swapped(token0, swappedAmount.intoUint256());
        }        
    }

    /// @notice returns the liquidity that will come, as a simulation
    function previewSwap(uint256 amount, bool useToken0) external returns (UD60x18 swappedAmount) {
        return _calculateSwap(amount, useToken0);
    }

    /// @notice how much of token1 will we get for a given token0 amount
    /// @dev factors in the protocol fee
    function _calculateSwap(uint256 amount, bool useToken0) internal returns (UD60x18 swappedAmount) {
        //.sub(ud(amount).mul(3).div(1000)));
        UD60x18 amountAdjustedForFee = ud(amount).sub(ud(amount).mul(ud(3)).div(ud(1000)));

        //calcuate so that the product would remain same
        UD60x18 existingK = _reserve0.mul(_reserve1);
        if (useToken0) {
            swappedAmount = _reserve1.sub(existingK.div(amountAdjustedForFee.add(_reserve0)));
        } else {
            swappedAmount = existingK.div(amountAdjustedForFee.add(_reserve1));
        }
    }

    /**
     * ERC4626 related
     */

    /// @notice this is hardwired to return 0
    function _convertToAssets(uint256 shares, Math.Rounding) internal view override returns (uint256) {
        return 0;
    }

    /// @notice this increases the precision of the underlying shares
    /// the idea is to make inflation attacks more expensive
    /// @dev however, since we are hardwiring assets to 0, this makes no difference
    function _decimalsOffset() internal view override returns (uint8) {
        return 18;
    }

    /// TBD: when lp tokens are returned, this acts as conversion to assets?

    /**
     * flash loan support
     */

    /// @dev as per whitepaper, same fee as for trading ie. 0.3%
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @return The amount of `token` to be charged for the loan, on top of the returned principal.
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        if (token1 != token && token0 != token) {
            revert NotPoolToken();
        }

        return ud(amount).mul(ud(3)).div(ud(1000)).intoUint256();
    }

    /// @notice The amount of currency available to be lended.
    /// @dev does not factor in fees
    /// @param token The loan currency.
    /// @return The amount of `token` that can be borrowed.
    function maxFlashLoan(address token) external view override returns (uint256) {
        if (token == token0) {
            return _reserve0.intoUint256();
        } else if (token == token1) {
            return _reserve1.intoUint256();
        } else {
            revert NotPoolToken();
        }
    }

    /// @dev Initiate a flash loan.
    /// @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        uint256 amountAvailableToLend;
        if (token == token0) {
            amountAvailableToLend = _reserve0.intoUint256();
        } else if (token == token1) {
            amountAvailableToLend = _reserve1.intoUint256();
        } else {
            revert NotPoolToken();
        }

        if (amountAvailableToLend < amount) {
            revert FlashLoanAmountTooMuch(amountAvailableToLend);
        }

        if (token == token0) {
            _reserve0 = _reserve0.sub(ud(amount));
        } else if (token == token1) {
            _reserve1 = _reserve1.sub(ud(amount));
        }

        if (!IERC20(token).transfer(address(receiver), amount))
            revert FlashLoanTransferToBorroweFailed();

        uint256 fee = flashFee(token, amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != CALLBACK_SUCCESS) {
            revert FlashLoanCallbackFailed();
        }

        uint256 totalExpectedBack = amount + fee;
        safeTransferFrom(ERC20(token), address(receiver), address(this), totalExpectedBack);
        if (token == token0) {
            _reserve0 = _reserve0.add(ud(totalExpectedBack));
        } else if (token == token1) {
            _reserve1 = 
            _reserve1.add(ud(totalExpectedBack));
        }

        emit FlashLoanReturned(address(receiver), token, amount);

        return true;
    }

    /// @notice this is copied from Solmate because "ERC20" was in both OZ and Solmate libraries
    /// is there a way to have namespaces in solidity?
    function safeTransferFrom(ERC20 token, address from, address to, uint256 amount) internal {
        bool success;

        /// @solidity memory-safe-assembly
        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), and(from, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "from" argument.
            mstore(add(freeMemoryPointer, 36), and(to, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "to" argument.
            mstore(add(freeMemoryPointer, 68), amount) // Append the "amount" argument. Masking not required as it's a full 32 byte type.

            success :=
                and(
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                    // We use 100 because the length of our calldata totals up like so: 4 + 32 * 3.
                    // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                    // Counterintuitively, this call must be positioned second to the or() call in the
                    // surrounding and() call or else returndatasize() will be zero during the computation.
                    call(gas(), token, 0, freeMemoryPointer, 100, 0, 32)
                )
        }

        require(success, "TRANSFER_FROM_FAILED");
    }
}
