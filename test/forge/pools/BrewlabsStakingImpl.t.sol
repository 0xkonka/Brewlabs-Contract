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

        swapAggregator.swapNoSplitFromETH(_trade, to);
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

        pool.deposit{value: _pool.performanceFee()}(1 ether);
        vm.stopPrank();
    }

    receive() external payable {}
}
