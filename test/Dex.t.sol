// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/Dex.sol";
import "../src/DexPool.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";

contract TokenWithSupply is ERC20 {
    constructor(string memory _name, string memory _symbol, uint256 initialSupply) ERC20(_name, _symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract FlashLoanBorrower is IERC3156FlashBorrower {
    address public lender;

    constructor(address _lender) {
        lender = _lender;
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        //require(initiator == address(this), "FlashBorrower: External loan initiator");
        IERC20(token).approve(lender, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract DexTest is Test {
    Dex public dex;

    ERC20 public tokenA;
    ERC20 public tokenB;
    address public account1 = vm.addr(0xABCD);
    address public account2 = vm.addr(0xDABC);
    address public account3 = vm.addr(0xCDAB);

    DexPool public pool;

    function setUp() public {
        dex = new Dex(300);
        tokenA = new TokenWithSupply("TokenA", "TA", 1000 ether);
        tokenB = new TokenWithSupply("TokenB", "TB", 1000 ether);

        string memory liquidityTokenName = string.concat(tokenA.name(), tokenB.name());
        string memory liquidityTokenSymbol = string.concat(tokenA.symbol(), tokenB.symbol());

        pool = DexPool(dex.startPool(address(tokenA), address(tokenB), liquidityTokenName, liquidityTokenSymbol));
        tokenA.transfer(account1, 50 ether);
        tokenB.transfer(account1, 50 ether);

        tokenA.transfer(account2, 50 ether);
        tokenB.transfer(account2, 50 ether);

        tokenA.transfer(account3, 50 ether);
        tokenB.transfer(account3, 50 ether);
    }

    function testAddLiquidity() public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 10 ether);
        tokenB.approve(address(pool), 20 ether);

        uint256 expectedLiquidity = pool.previewDeposit(10 ether, 20 ether);
        pool.depositPair(10 ether, 20 ether);

        vm.stopPrank();

        require(pool.balanceOf(account1) == expectedLiquidity, "lp tokens not as expected");
    }

    function testFailIfNotInCorrectProportion() public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 20 ether);
        tokenB.approve(address(pool), 40 ether);
        pool.depositPair(10 ether, 20 ether);
        pool.depositPair(10 ether, 10 ether);
        vm.stopPrank();
    }

    function testFailIfInsufficientAllowance() public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 9 ether);
        tokenB.approve(address(pool), 19 ether);
        pool.depositPair(10 ether, 20 ether);
        vm.stopPrank();
    }

    function testAddLiquidityTwice() public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 50 ether);
        tokenB.approve(address(pool), 50 ether);

        uint256 expectedLiquidity = pool.previewDeposit(10 ether, 20 ether);
        pool.depositPair(10 ether, 20 ether);
        expectedLiquidity += pool.previewDeposit(15 ether, 30 ether);
        pool.depositPair(15 ether, 30 ether);
        vm.stopPrank();

        require(pool.balanceOf(account1) == expectedLiquidity, "lp tokens not as expected");
    }

    /// @notice get liquidity with a deposit and then redeem it full
    /// should end up with the same balance as we began with (from setup)
    function testRemoveLiquidity() public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 10 ether);
        tokenB.approve(address(pool), 20 ether);
        uint256 expectedLiquidity = pool.previewDeposit(10 ether, 20 ether);
        pool.depositPair(10 ether, 20 ether);

        uint256 poolBalanceForAccount1 = pool.balanceOf(account1);
        require(poolBalanceForAccount1 == expectedLiquidity, "lp tokens not as expected");

        // uint256 balanceBeforeA = tokenA.balanceOf(account1);
        // uint256 balanceBeforeB = tokenB.balanceOf(account1);

        pool.redeem(poolBalanceForAccount1, account1, account1);
        vm.stopPrank();

        require(tokenA.balanceOf(account1) == 50 ether, "balance not as expected");
        require(tokenB.balanceOf(account1) == 50 ether, "balance not as expected");
    }

    function testSwapping(uint256 x) public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 5 ether);
        tokenB.approve(address(pool), 20 ether);
        pool.depositPair(5 ether, 20 ether);
        vm.stopPrank();

        uint256 balanceBefore = tokenB.balanceOf(account2);
        //send in tokenA, get tokenB in return
        vm.startPrank(account2);
        tokenA.approve(address(pool), 1 ether);
        pool.swap(0.001 ether, true, 0);
        //require(tokenB.balanceOf(account2))

        vm.stopPrank();

        uint256 amountReduced = 20 ether - (tokenB.balanceOf(address(pool)));
        uint256 amountGained = tokenB.balanceOf(account2) - balanceBefore;

        require(amountReduced == amountGained, "accounting doesnt line up");
    }

    function testFlashLoan() public {
        vm.startPrank(account1);
        tokenA.approve(address(pool), 10 ether);
        tokenB.approve(address(pool), 20 ether);
        pool.depositPair(10 ether, 20 ether);
        vm.stopPrank();
        vm.startPrank(account3);
        FlashLoanBorrower borrower = new FlashLoanBorrower(address(pool));
        uint256 amountToBorrow = 10 ether;
        uint256 feeAmount = pool.flashFee(address(tokenA), amountToBorrow);
        tokenA.transfer(address(borrower), feeAmount);
        pool.flashLoan(borrower, address(tokenA), amountToBorrow, "");
        vm.stopPrank();
    }
}
