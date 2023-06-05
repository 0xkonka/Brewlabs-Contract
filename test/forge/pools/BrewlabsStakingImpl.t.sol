// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsStakingImpl, IBrewlabsAggregator, IERC20} from "../../../contracts/pool/BrewlabsStakingImpl.sol";
import {BrewlabsPoolFactory} from "../../../contracts/pool/BrewlabsPoolFactory.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsStakingImplTest is Test {
    address internal BREWLABS = 0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7;
    address internal BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address internal WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address internal poolOwner = address(0x111);
    address internal deployer = address(0x123);

    uint256 internal FEE_DENOMINATOR = 10000;
    uint256 internal DEPOSIT_FEE = 10;
    uint256 internal WITHDRAW_FEE = 20;

    BrewlabsPoolFactory internal factory;
    BrewlabsStakingImpl internal pool;
    MockErc20 internal stakingToken;
    MockErc20 internal rewardToken;
    MockErc20 internal dividendToken;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event ClaimDividend(address indexed user, uint256 amount);
    event Compound(address indexed user, uint256 amount);
    event CompoundDividend(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event RewardsStop(uint256 blockNumber);
    event EndBlockChanged(uint256 blockNumber);
    event UpdatePoolLimit(uint256 poolLimitPerUser, bool hasLimit);

    event ServiceInfoChanged(address _addr, uint256 _fee);
    event WalletAUpdated(address _addr);
    event DurationChanged(uint256 _duration);
    event OperatorTransferred(address oldOperator, address newOperator);
    event SetAutoAdjustableForRewardRate(bool status);
    event SetWhiteList(address _whitelist);
    event SetSwapAggregator(address aggregator);

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();

        BrewlabsStakingImpl impl = new BrewlabsStakingImpl();

        stakingToken = new MockErc20(18);
        rewardToken = stakingToken;
        dividendToken = new MockErc20(18);

        factory = new BrewlabsPoolFactory();
        factory.initialize(address(stakingToken), 0, poolOwner);
        factory.setImplementation(0, address(impl));

        vm.startPrank(deployer);
        pool = BrewlabsStakingImpl(
            payable(
                factory.createBrewlabsSinglePool(
                    stakingToken, rewardToken, address(dividendToken), 365, 1 ether, DEPOSIT_FEE, WITHDRAW_FEE, true
                )
            )
        );
        stakingToken.mint(address(pool), pool.insufficientRewards());
        pool.startReward();

        utils.mineBlocks(101);

        vm.stopPrank();
    }

    function trySwap(address token, uint256 amount, address to) internal {
        IBrewlabsAggregator swapAggregator = pool.swapAggregator();
        IBrewlabsAggregator.FormattedOffer memory query = swapAggregator.findBestPath(amount, WBNB, token, 3);

        IBrewlabsAggregator.Trade memory _trade;
        _trade.amountIn = amount;
        _trade.amountOut = query.amounts[query.amounts.length - 1];
        _trade.adapters = query.adapters;
        _trade.path = query.path;

        swapAggregator.swapNoSplitFromETH{value: amount}(_trade, to);
    }

    function tryDeposit(address _user, uint256 _amount) internal {
        stakingToken.mint(_user, _amount);
        vm.deal(_user, pool.performanceFee());

        vm.startPrank(_user);
        stakingToken.approve(address(pool), _amount);

        pool.deposit{value: pool.performanceFee()}(_amount);
        vm.stopPrank();
    }

    function test_firstDeposit() public {
        uint256 treasuryVal = address(pool.treasury()).balance;

        address _user = address(0x1);
        uint256 _amount = 1 ether;
        uint256 performanceFee = pool.performanceFee();
        stakingToken.mint(_user, _amount);
        vm.deal(_user, performanceFee);

        vm.startPrank(_user);
        stakingToken.approve(address(pool), _amount);

        uint256 _depositFee = _amount * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, _amount - _depositFee);
        pool.deposit{value: performanceFee}(_amount);

        (uint256 amount, uint256 rewardDebt, uint256 reflectionDebt) = pool.userInfo(address(0x1));
        assertEq(amount, 1 ether - _depositFee);
        assertEq(stakingToken.balanceOf(pool.walletA()), _depositFee);
        assertEq(pool.totalStaked(), 1 ether - _depositFee);
        assertEq(rewardDebt, 0);
        assertEq(reflectionDebt, 0);
        assertEq(address(pool.treasury()).balance - treasuryVal, performanceFee);

        vm.expectRevert(abi.encodePacked("Amount should be greator than 0"));
        pool.deposit(0);
        vm.stopPrank();
    }

    function test_notFirstDeposit() public {
        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(100);

        (uint256 amount,,) = pool.userInfo(address(0x1));
        uint256 _reward = 100 * pool.rewardPerBlock();
        uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

        uint256 pending = pool.pendingReward(address(0x1));
        uint256 pendingReflection = pool.pendingDividends(address(0x1));
        assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

        tryDeposit(address(0x1), 1 ether);
        assertEq(stakingToken.balanceOf(address(0x1)), pending);
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(pool.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(pool.availableRewardTokens(), rewards - pending);
        assertEq(pool.paidRewards(), pending);
    }

    function testFailed_depositInNotStaredPool() public {
        BrewlabsStakingImpl _pool = BrewlabsStakingImpl(
            payable(
                factory.createBrewlabsSinglePool(
                    stakingToken, rewardToken, address(0x0), 365, 1 ether, DEPOSIT_FEE, WITHDRAW_FEE, false
                )
            )
        );

        stakingToken.mint(address(0x1), 1 ether);
        vm.deal(address(0x1), _pool.performanceFee());

        vm.startPrank(address(0x1));
        stakingToken.approve(address(_pool), 1 ether);

        _pool.deposit{value: _pool.performanceFee()}(1 ether);
        vm.stopPrank();
    }

    function testFailed_zeroDeposit() public {
        tryDeposit(address(0x1), 0);
    }

    function testFailed_depositInNotEnoughRewards() public {
        tryDeposit(address(0x1), 1 ether);

        vm.startPrank(deployer);
        pool.updateRewardPerBlock(100 ether);
        vm.stopPrank();

        vm.roll(pool.bonusEndBlock() - 100);

        tryDeposit(address(0x1), 1 ether);
    }

    function test_pendingReward() public {
        tryDeposit(address(0x1), 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        utils.mineBlocks(1000);

        (uint256 amount, uint256 rewardDebt,) = pool.userInfo(address(0x1));

        uint256 rewards = 1000 * pool.rewardPerBlock();
        uint256 accTokenPerShare = pool.accTokenPerShare() + rewards * pool.PRECISION_FACTOR() / pool.totalStaked();
        uint256 pending = amount * accTokenPerShare / pool.PRECISION_FACTOR() - rewardDebt;
        assertEq(pool.pendingReward(address(0x1)), pending);

        utils.mineBlocks(100);
        rewards = 1100 * pool.rewardPerBlock();
        accTokenPerShare = pool.accTokenPerShare() + rewards * pool.PRECISION_FACTOR() / pool.totalStaked();
        pending = amount * accTokenPerShare / pool.PRECISION_FACTOR() - rewardDebt;
        assertEq(pool.pendingReward(address(0x1)), pending);
    }

    function test_pendingDividends() public {
        tryDeposit(address(0x1), 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        dividendToken.mint(address(pool), 0.01 ether);

        utils.mineBlocks(1000);
        uint256 reflectionAmt = pool.availableDividendTokens();
        uint256 accReflectionPerShare = pool.accDividendPerShare()
            + reflectionAmt * pool.PRECISION_FACTOR_REFLECTION() / (pool.totalStaked() + pool.availableRewardTokens());

        (uint256 amount,, uint256 reflectionDebt) = pool.userInfo(address(0x1));

        uint256 pending = amount * accReflectionPerShare / pool.PRECISION_FACTOR_REFLECTION() - reflectionDebt;
        assertEq(pool.pendingDividends(address(0x1)), pending);
    }

    function test_withdraw() public {
        tryDeposit(address(0x1), 2 ether);

        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        utils.mineBlocks(100);

        (uint256 amount,,) = pool.userInfo(address(0x1));
        uint256 _reward = 100 * pool.rewardPerBlock();
        uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

        uint256 pending = pool.pendingReward(address(0x1));
        uint256 pendingReflection = pool.pendingDividends(address(0x1));
        assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

        uint256 performanceFee = pool.performanceFee();

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        vm.expectRevert("Amount should be greator than 0");
        pool.withdraw{value: performanceFee}(0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(0x1), 1 ether);
        pool.withdraw{value: performanceFee}(1 ether);

        vm.stopPrank();

        assertEq(stakingToken.balanceOf(address(0x1)), 1 ether - 1 ether * WITHDRAW_FEE / 10000 + pending);
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(pool.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(pool.availableRewardTokens(), rewards - pending);
        assertEq(pool.paidRewards(), pending);
    }

    function testFailed_withdrawInExceedAmount() public {
        tryDeposit(address(0x1), 1 ether);

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        pool.withdraw{value: pool.performanceFee()}(2 ether);

        vm.stopPrank();
    }

    function testFailed_withdrawInNotEnoughRewards() public {
        tryDeposit(address(0x1), 1 ether);

        vm.startPrank(deployer);
        pool.updateRewardPerBlock(100 ether);
        vm.stopPrank();

        vm.roll(pool.bonusEndBlock() - 100);

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        pool.withdraw{value: pool.performanceFee()}(0.5 ether);

        vm.stopPrank();
    }

    function test_claimReward() public {
        tryDeposit(address(0x1), 2 ether);

        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        utils.mineBlocks(100);

        (uint256 amount,,) = pool.userInfo(address(0x1));
        uint256 _reward = 100 * pool.rewardPerBlock();
        uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

        uint256 pending = pool.pendingReward(address(0x1));
        assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

        uint256 performanceFee = pool.performanceFee();

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        uint256 tokenBal = stakingToken.balanceOf(address(0x1));

        vm.expectEmit(true, true, true, true);
        emit Claim(address(0x1), pending);
        pool.claimReward{value: performanceFee}();

        vm.stopPrank();

        assertEq(stakingToken.balanceOf(address(0x1)), tokenBal + pending);
        assertEq(dividendToken.balanceOf(address(0x1)), 0);

        assertEq(pool.availableDividendTokens(), 0.1 ether);
        assertEq(pool.availableRewardTokens(), rewards - pending);
        assertEq(pool.paidRewards(), pending);
    }

    function test_compoundReward() public {
        tryDeposit(address(0x1), 2 ether);

        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        utils.mineBlocks(100);

        (uint256 amount,,) = pool.userInfo(address(0x1));
        uint256 _reward = 100 * pool.rewardPerBlock();
        uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

        uint256 pending = pool.pendingReward(address(0x1));
        assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

        uint256 performanceFee = pool.performanceFee();

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        uint256 tokenBal = stakingToken.balanceOf(address(0x1));

        IBrewlabsAggregator.FormattedOffer memory query = pool.precomputeCompoundReward();
        IBrewlabsAggregator.Trade memory trade;
        trade.adapters = query.adapters;
        trade.path = query.path;

        vm.expectEmit(true, true, true, true);
        emit Compound(address(0x1), pending);
        pool.compoundReward{value: performanceFee}(trade);

        vm.stopPrank();

        (uint256 amount1,,) = pool.userInfo(address(0x1));
        assertEq(amount1, amount + pending);
        assertEq(stakingToken.balanceOf(address(0x1)), tokenBal);
        assertEq(dividendToken.balanceOf(address(0x1)), 0);

        assertEq(pool.availableDividendTokens(), 0.1 ether);
        assertEq(pool.availableRewardTokens(), rewards - pending);
        assertEq(pool.paidRewards(), pending);
    }

    function test_claimDividend() public {
        tryDeposit(address(0x1), 2 ether);

        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        utils.mineBlocks(100);

        uint256 pendingReflection = pool.pendingDividends(address(0x1));
        uint256 performanceFee = pool.performanceFee();

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        uint256 tokenBal = dividendToken.balanceOf(address(0x1));

        vm.expectEmit(true, true, true, true);
        emit ClaimDividend(address(0x1), pendingReflection);
        pool.claimDividend{value: performanceFee}();

        vm.stopPrank();

        assertEq(stakingToken.balanceOf(address(0x1)), 0);
        assertEq(dividendToken.balanceOf(address(0x1)), tokenBal + pendingReflection);

        assertEq(pool.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(pool.availableRewardTokens(), rewards);
    }

    function test_compoundDividend() public {
        BrewlabsStakingImpl _pool = BrewlabsStakingImpl(
            payable(
                factory.createBrewlabsSinglePool(IERC20(BREWLABS), IERC20(BREWLABS), BUSD, 10, 0.001 gwei, 0, 0, true)
            )
        );

        trySwap(BREWLABS, 1 ether, address(_pool));

        uint256 rewards = _pool.availableRewardTokens();
        _pool.startReward();
        utils.mineBlocks(101);

        address _user = address(0x1);
        trySwap(BREWLABS, 0.1 ether, _user);
        uint256 _amount = IERC20(BREWLABS).balanceOf(_user);

        vm.deal(_user, 1 ether);
        vm.startPrank(_user);
        IERC20(BREWLABS).approve(address(_pool), _amount);
        _pool.deposit{value: _pool.performanceFee()}(_amount);
        vm.stopPrank();

        trySwap(BUSD, 0.1 ether, address(_pool));
        uint256 busdBal = IERC20(BUSD).balanceOf(address(_pool));

        utils.mineBlocks(100);

        (uint256 amount,,) = _pool.userInfo(address(0x1));
        uint256 pendingReflection = _pool.pendingDividends(address(0x1));
        uint256 performanceFee = _pool.performanceFee();
        uint256 tokenBal = IERC20(BUSD).balanceOf(address(0x1));

        vm.startPrank(_user);

        IBrewlabsAggregator.FormattedOffer memory query = _pool.precomputeCompoundDividend();
        IBrewlabsAggregator.Trade memory trade;
        trade.adapters = query.adapters;
        trade.path = query.path;

        vm.expectEmit(true, true, true, true);
        emit CompoundDividend(address(0x1), pendingReflection);
        _pool.compoundDividend{value: performanceFee}(trade);

        vm.stopPrank();

        (uint256 amount1,,) = _pool.userInfo(address(0x1));
        assertGt(amount1, amount);
        assertEq(_pool.pendingDividends(_user), 0);
        assertEq(IERC20(BREWLABS).balanceOf(address(0x1)), 0);
        assertEq(IERC20(BUSD).balanceOf(address(0x1)), tokenBal);

        assertEq(_pool.availableDividendTokens(), busdBal - pendingReflection);
        assertEq(_pool.availableRewardTokens(), rewards);
    }

    function test_harvestTo() public {
        tryDeposit(address(0x1), 2 ether);

        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        utils.mineBlocks(100);

        (uint256 amount,,) = pool.userInfo(address(0x1));
        uint256 _reward = 100 * pool.rewardPerBlock();
        uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

        uint256 pending = pool.pendingReward(address(0x1));
        assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

        uint256 performanceFee = pool.performanceFee();

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));

        uint256 tokenBal = stakingToken.balanceOf(address(0x1));

        vm.expectEmit(true, true, true, true);
        emit Claim(address(0x1), pending);
        pool.claimReward{value: performanceFee}();

        vm.stopPrank();

        assertEq(stakingToken.balanceOf(address(0x1)), tokenBal + pending);
        assertEq(dividendToken.balanceOf(address(0x1)), 0);

        assertEq(pool.availableDividendTokens(), 0.1 ether);
        assertEq(pool.availableRewardTokens(), rewards - pending);
        assertEq(pool.paidRewards(), pending);
    }

    receive() external payable {}
}
