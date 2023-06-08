// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsLockupImpl, IBrewlabsAggregator, IERC20} from "../../../contracts/pool/BrewlabsLockupImpl.sol";
import {BrewlabsPoolFactory} from "../../../contracts/pool/BrewlabsPoolFactory.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsLockupImplTest is Test {
    address internal BREWLABS = 0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7;
    address internal BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address internal WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address internal poolOwner = address(0x111);
    address internal deployer = address(0x123);

    uint256 internal FEE_DENOMINATOR = 10000;
    uint256 internal DEPOSIT_FEE = 10;
    uint256 internal WITHDRAW_FEE = 20;
    uint256 internal BLOCKS_PER_DAY = 28800;

    BrewlabsPoolFactory internal factory;
    BrewlabsLockupImpl internal pool;
    MockErc20 internal stakingToken;
    MockErc20 internal rewardToken;
    MockErc20 internal dividendToken;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    event Deposit(address indexed user, uint256 stakeType, uint256 amount);
    event Withdraw(address indexed user, uint256 stakeType, uint256 amount);
    event Claim(address indexed user, uint256 stakeType, uint256 amount);
    event ClaimDividend(address indexed user, uint256 stakeType, uint256 amount);
    event Compound(address indexed user, uint256 stakeType, uint256 amount);
    event CompoundDividend(address indexed user, uint256 stakeType, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);
    event SetEmergencyWithdrawStatus(bool status);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event LockupUpdated(uint8 _type, uint256 _duration, uint256 _fee0, uint256 _fee1, uint256 _rate);
    event RewardsStop(uint256 blockNumber);
    event EndBlockChanged(uint256 blockNumber);
    event UpdatePoolLimit(uint256 poolLimitPerUser, bool hasLimit);

    event ServiceInfoChanged(address _addr, uint256 _fee);
    event DurationChanged(uint256 _duration);
    event OperatorTransferred(address oldOperator, address newOperator);
    event SetWhiteList(address _whitelist);
    event SetSwapAggregator(address aggregator);

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();

        BrewlabsLockupImpl impl = new BrewlabsLockupImpl();

        stakingToken = new MockErc20(18);
        rewardToken = stakingToken;
        dividendToken = new MockErc20(18);

        factory = new BrewlabsPoolFactory();
        factory.initialize(address(stakingToken), 0, poolOwner);
        factory.setImplementation(1, address(impl));

        vm.startPrank(deployer);

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 10;
        lockDurations[1] = 20;

        uint256[] memory rewardsPerBlock = new uint256[](2);
        rewardsPerBlock[0] = 1 ether;
        rewardsPerBlock[1] = 1.5 ether;

        uint256[] memory depositFees = new uint256[](2);
        depositFees[0] = 0;
        depositFees[1] = DEPOSIT_FEE;

        uint256[] memory withdrawFees = new uint256[](2);
        withdrawFees[0] = 0;
        withdrawFees[1] = WITHDRAW_FEE;

        pool = BrewlabsLockupImpl(
            payable(
                factory.createBrewlabsLockupPools(
                    address(stakingToken),
                    address(rewardToken),
                    address(dividendToken),
                    365,
                    lockDurations,
                    rewardsPerBlock,
                    depositFees,
                    withdrawFees
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

        pool.deposit{value: pool.performanceFee()}(_amount, 0);
        vm.stopPrank();
    }

    function test_firstDeposit() public {
        address _user = address(0x1);
        uint256 _amount = 1 ether;
        uint256 performanceFee = pool.performanceFee();
        stakingToken.mint(_user, _amount);
        vm.deal(_user, 1 ether);

        vm.startPrank(_user);
        stakingToken.approve(address(pool), _amount);

        (,, uint256 depositFee,,,,,,) = pool.lockups(uint256(0));

        uint256 treasuryVal = address(pool.treasury()).balance;
        uint256 _depositFee = (_amount * depositFee) / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, 0, 1 ether - _depositFee);
        pool.deposit{value: performanceFee}(_amount, 0);

        (,,,,,,, uint256 totalStaked,) = pool.lockups(uint256(0));
        (uint256 amount, uint256 available, uint256 locked) = pool.userInfo(0, address(0x1));
        assertEq(amount, 1 ether - _depositFee);
        assertEq(available, 0);
        assertEq(locked, 1 ether - _depositFee);

        assertEq(stakingToken.balanceOf(pool.walletA()), _depositFee);
        assertEq(totalStaked, 1 ether - _depositFee);
        assertEq(address(pool.treasury()).balance - treasuryVal, pool.performanceFee());

        vm.expectRevert("Amount should be greator than 0");
        pool.deposit{value: performanceFee}(0, 0);
        vm.stopPrank();
    }

    function test_notFirstDeposit() public {
        dividendToken.mint(address(pool), 0.1 ether);
        uint256 rewards = pool.availableRewardTokens();

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(100);

        (uint256 amount,,) = pool.userInfo(0, address(0x1));
        uint256 _reward = 100 * pool.rewardPerBlock(0);
        uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

        uint256 pending = pool.pendingReward(address(0x1), 0);
        uint256 pendingReflection = pool.pendingDividends(address(0x1), 0);
        assertEq(pending, (amount * accTokenPerShare) / pool.PRECISION_FACTOR());

        tryDeposit(address(0x1), 1 ether);
        assertEq(stakingToken.balanceOf(address(0x1)), pending);
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(pool.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(pool.availableRewardTokens(), rewards - pending);
        assertEq(pool.paidRewards(), pending);
    }

    function testFailed_depositInNotStaredPool() public {
        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 10;
        lockDurations[1] = 20;

        uint256[] memory rewardsPerBlock = new uint256[](2);
        rewardsPerBlock[0] = 1 ether;
        rewardsPerBlock[1] = 1.5 ether;

        uint256[] memory depositFees = new uint256[](2);
        depositFees[0] = 0;
        depositFees[1] = DEPOSIT_FEE;

        uint256[] memory withdrawFees = new uint256[](2);
        withdrawFees[0] = 0;
        withdrawFees[1] = WITHDRAW_FEE;

        BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
            payable(
                factory.createBrewlabsLockupPools(
                    address(stakingToken),
                    address(rewardToken),
                    address(0x0),
                    365,
                    lockDurations,
                    rewardsPerBlock,
                    depositFees,
                    withdrawFees
                )
            )
        );

        stakingToken.mint(address(0x1), 1 ether);
        vm.deal(address(0x1), _pool.performanceFee());

        vm.startPrank(address(0x1));
        stakingToken.approve(address(_pool), 1 ether);

        _pool.deposit{value: _pool.performanceFee()}(1 ether, 0);
        vm.stopPrank();
    }

    function testFailed_zeroDeposit() public {
        tryDeposit(address(0x1), 0);
    }

    function testFailed_depositInNotEnoughRewards() public {
        tryDeposit(address(0x1), 1 ether);

        vm.startPrank(deployer);
        pool.updateLockup(0, 20, 0, 0, 100 ether, 0);
        vm.stopPrank();

        vm.roll(pool.bonusEndBlock() - 100);

        tryDeposit(address(0x1), 1 ether);
    }

    function test_pendingReward() public {
        tryDeposit(address(0x1), 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        utils.mineBlocks(1000);

        (
            uint8 stakeType,
            uint256 duration,
            uint256 depositFee,
            uint256 withdrawFee,
            uint256 rate,
            uint256 accTokenPerShare,
            uint256 lastRewardBlock,
            uint256 totalStaked,
            uint256 totalStakedLimit
        ) = pool.lockups(0);

        uint256 multiplier = block.number - lastRewardBlock;
        uint256 reward = multiplier * rate;
        accTokenPerShare += (reward * pool.PRECISION_FACTOR()) / totalStaked;

        uint256 pending = 0;
        for (uint256 i = 0; i < 2; i++) {
            (
                uint8 _stakeType,
                uint256 amount,
                uint256 duration,
                uint256 end,
                uint256 rewardDebt,
                uint256 reflectionDebt
            ) = pool.userStakes(address(0x1), i);
            if (stakeType != _stakeType) continue;
            pending += (amount * accTokenPerShare) / pool.PRECISION_FACTOR() - rewardDebt;
        }

        // assertEq(pool.pendingReward(address(0x1), 0), pending);

        // uint256 rewards = 1000 * pool.rewardPerBlock(0);
        // uint256 accTokenPerShare = lockup.accTokenPerShare + rewards * pool.PRECISION_FACTOR() / pool.totalStaked();
        // uint256 pending = amount * accTokenPerShare / pool.PRECISION_FACTOR() - rewardDebt;
        // utils.mineBlocks(100);
        // rewards = 1100 * pool.rewardPerBlock(0);
        // accTokenPerShare = pool.accTokenPerShare + rewards * pool.PRECISION_FACTOR() / pool.totalStaked();
        // pending = amount * accTokenPerShare / pool.PRECISION_FACTOR() - rewardDebt;
        // assertEq(pool.pendingReward(address(0x1)), pending);
    }

    // function test_pendingDividends() public {
    //     tryDeposit(address(0x1), 1 ether);
    //     utils.mineBlocks(2);
    //     tryDeposit(address(0x2), 2 ether);

    //     dividendToken.mint(address(pool), 0.01 ether);

    //     utils.mineBlocks(1000);
    //     uint256 reflectionAmt = pool.availableDividendTokens();
    //     uint256 accReflectionPerShare = pool.accDividendPerShare()
    //         + reflectionAmt * pool.PRECISION_FACTOR_REFLECTION() / (pool.totalStaked() + pool.availableRewardTokens());

    //     (uint256 amount,, uint256 reflectionDebt) = pool.userInfo(address(0x1));

    //     uint256 pending = amount * accReflectionPerShare / pool.PRECISION_FACTOR_REFLECTION() - reflectionDebt;
    //     assertEq(pool.pendingDividends(address(0x1)), pending);
    // }

    // function test_withdraw() public {
    //     tryDeposit(address(0x1), 2 ether);

    //     dividendToken.mint(address(pool), 0.1 ether);
    //     uint256 rewards = pool.availableRewardTokens();

    //     utils.mineBlocks(100);

    //     (uint256 amount,,) = pool.userInfo(address(0x1));
    //     uint256 _reward = 100 * pool.rewardPerBlock();
    //     uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

    //     uint256 pending = pool.pendingReward(address(0x1));
    //     uint256 pendingReflection = pool.pendingDividends(address(0x1));
    //     assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

    //     uint256 performanceFee = pool.performanceFee();

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     vm.expectRevert("Amount should be greator than 0");
    //     pool.withdraw{value: performanceFee}(0);

    //     vm.expectEmit(true, true, true, true);
    //     emit Withdraw(address(0x1), 1 ether);
    //     pool.withdraw{value: performanceFee}(1 ether);

    //     vm.stopPrank();

    //     assertEq(stakingToken.balanceOf(address(0x1)), 1 ether - 1 ether * WITHDRAW_FEE / 10000 + pending);
    //     assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

    //     assertEq(pool.availableDividendTokens(), 0.1 ether - pendingReflection);
    //     assertEq(pool.availableRewardTokens(), rewards - pending);
    //     assertEq(pool.paidRewards(), pending);
    // }

    // function testFailed_withdrawInExceedAmount() public {
    //     tryDeposit(address(0x1), 1 ether);

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     pool.withdraw{value: pool.performanceFee()}(2 ether);

    //     vm.stopPrank();
    // }

    // function testFailed_withdrawInNotEnoughRewards() public {
    //     tryDeposit(address(0x1), 1 ether);

    //     vm.startPrank(deployer);
    //     pool.updateRewardPerBlock(100 ether);
    //     vm.stopPrank();

    //     vm.roll(pool.bonusEndBlock() - 100);

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     pool.withdraw{value: pool.performanceFee()}(0.5 ether);

    //     vm.stopPrank();
    // }

    // function test_emergencyWithdraw() public {
    //     tryDeposit(address(0x1), 2 ether);

    //     dividendToken.mint(address(pool), 0.1 ether);
    //     uint256 rewards = pool.availableRewardTokens();

    //     utils.mineBlocks(100);

    //     (uint256 amount,,) = pool.userInfo(address(0x1));

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     vm.expectEmit(true, true, true, true);
    //     emit EmergencyWithdraw(address(0x1), amount);
    //     pool.emergencyWithdraw();

    //     vm.stopPrank();

    //     assertEq(stakingToken.balanceOf(address(0x1)), amount);
    //     assertEq(dividendToken.balanceOf(address(0x1)), 0);

    //     assertEq(pool.availableDividendTokens(), 0.1 ether);
    //     assertEq(pool.availableRewardTokens(), rewards);
    //     assertEq(pool.paidRewards(), 0);
    // }

    // function test_claimReward() public {
    //     tryDeposit(address(0x1), 2 ether);

    //     dividendToken.mint(address(pool), 0.1 ether);
    //     uint256 rewards = pool.availableRewardTokens();

    //     utils.mineBlocks(100);

    //     (uint256 amount,,) = pool.userInfo(address(0x1));
    //     uint256 _reward = 100 * pool.rewardPerBlock();
    //     uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

    //     uint256 pending = pool.pendingReward(address(0x1));
    //     assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

    //     uint256 performanceFee = pool.performanceFee();

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     uint256 tokenBal = stakingToken.balanceOf(address(0x1));

    //     vm.expectEmit(true, true, true, true);
    //     emit Claim(address(0x1), pending);
    //     pool.claimReward{value: performanceFee}();

    //     vm.stopPrank();

    //     assertEq(stakingToken.balanceOf(address(0x1)), tokenBal + pending);
    //     assertEq(dividendToken.balanceOf(address(0x1)), 0);

    //     assertEq(pool.availableDividendTokens(), 0.1 ether);
    //     assertEq(pool.availableRewardTokens(), rewards - pending);
    //     assertEq(pool.paidRewards(), pending);
    // }

    // // function test_compoundReward() public {
    // //     tryDeposit(address(0x1), 2 ether);

    // //     dividendToken.mint(address(pool), 0.1 ether);
    // //     uint256 rewards = pool.availableRewardTokens();

    // //     utils.mineBlocks(100);

    // //     (uint256 amount,,) = pool.userInfo(address(0x1));
    // //     uint256 _reward = 100 * pool.rewardPerBlock();
    // //     uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

    // //     uint256 pending = pool.pendingReward(address(0x1));
    // //     assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

    // //     uint256 performanceFee = pool.performanceFee();

    // //     vm.deal(address(0x1), 1 ether);
    // //     vm.startPrank(address(0x1));

    // //     uint256 tokenBal = stakingToken.balanceOf(address(0x1));

    // //     IBrewlabsAggregator.FormattedOffer memory query = pool.precomputeCompound(false);
    // //     IBrewlabsAggregator.Trade memory trade;
    // //     trade.adapters = query.adapters;
    // //     trade.path = query.path;

    // //     vm.expectEmit(true, true, true, true);
    // //     emit Compound(address(0x1), pending);
    // //     pool.compoundReward{value: performanceFee}(trade);

    // //     vm.stopPrank();

    // //     (uint256 amount1,,) = pool.userInfo(address(0x1));
    // //     assertEq(amount1, amount + pending);
    // //     assertEq(stakingToken.balanceOf(address(0x1)), tokenBal);
    // //     assertEq(dividendToken.balanceOf(address(0x1)), 0);

    // //     assertEq(pool.availableDividendTokens(), 0.1 ether);
    // //     assertEq(pool.availableRewardTokens(), rewards - pending);
    // //     assertEq(pool.paidRewards(), pending);
    // // }

    // function test_claimDividend() public {
    //     tryDeposit(address(0x1), 2 ether);

    //     dividendToken.mint(address(pool), 0.1 ether);
    //     uint256 rewards = pool.availableRewardTokens();

    //     utils.mineBlocks(100);

    //     uint256 pendingReflection = pool.pendingDividends(address(0x1));
    //     uint256 performanceFee = pool.performanceFee();

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     uint256 tokenBal = dividendToken.balanceOf(address(0x1));

    //     vm.expectEmit(true, true, true, true);
    //     emit ClaimDividend(address(0x1), pendingReflection);
    //     pool.claimDividend{value: performanceFee}();

    //     vm.stopPrank();

    //     assertEq(stakingToken.balanceOf(address(0x1)), 0);
    //     assertEq(dividendToken.balanceOf(address(0x1)), tokenBal + pendingReflection);

    //     assertEq(pool.availableDividendTokens(), 0.1 ether - pendingReflection);
    //     assertEq(pool.availableRewardTokens(), rewards);
    // }

    // // function test_compoundDividend() public {
    // //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    // //         payable(
    // //             factory.createBrewlabsSinglePool(IERC20(BREWLABS), IERC20(BREWLABS), BUSD, 10, 0.001 gwei, 0, 0, true)
    // //         )
    // //     );

    // //     trySwap(BREWLABS, 1 ether, address(_pool));

    // //     uint256 rewards = _pool.availableRewardTokens();
    // //     _pool.startReward();
    // //     utils.mineBlocks(101);

    // //     address _user = address(0x1);
    // //     trySwap(BREWLABS, 0.1 ether, _user);
    // //     uint256 _amount = IERC20(BREWLABS).balanceOf(_user);

    // //     vm.deal(_user, 1 ether);
    // //     vm.startPrank(_user);
    // //     IERC20(BREWLABS).approve(address(_pool), _amount);
    // //     _pool.deposit{value: _pool.performanceFee()}(_amount);
    // //     vm.stopPrank();

    // //     trySwap(BUSD, 0.1 ether, address(_pool));
    // //     uint256 busdBal = IERC20(BUSD).balanceOf(address(_pool));

    // //     utils.mineBlocks(100);

    // //     (uint256 amount,,) = _pool.userInfo(address(0x1));
    // //     uint256 pendingReflection = _pool.pendingDividends(address(0x1));
    // //     uint256 performanceFee = _pool.performanceFee();
    // //     uint256 tokenBal = IERC20(BUSD).balanceOf(address(0x1));

    // //     vm.startPrank(_user);

    // //     IBrewlabsAggregator.FormattedOffer memory query = _pool.precomputeCompound(true);
    // //     IBrewlabsAggregator.Trade memory trade;
    // //     trade.adapters = query.adapters;
    // //     trade.path = query.path;

    // //     vm.expectEmit(true, true, true, true);
    // //     emit CompoundDividend(address(0x1), pendingReflection);
    // //     _pool.compoundDividend{value: performanceFee}(trade);

    // //     vm.stopPrank();

    // //     (uint256 amount1,,) = _pool.userInfo(address(0x1));
    // //     assertGt(amount1, amount);
    // //     assertEq(_pool.pendingDividends(_user), 0);
    // //     assertEq(IERC20(BREWLABS).balanceOf(address(0x1)), 0);
    // //     assertEq(IERC20(BUSD).balanceOf(address(0x1)), tokenBal);

    // //     assertEq(_pool.availableDividendTokens(), busdBal - pendingReflection);
    // //     assertEq(_pool.availableRewardTokens(), rewards);
    // // }

    // function test_harvestTo() public {
    //     tryDeposit(address(0x1), 2 ether);

    //     dividendToken.mint(address(pool), 0.1 ether);
    //     uint256 rewards = pool.availableRewardTokens();

    //     utils.mineBlocks(100);

    //     (uint256 amount,,) = pool.userInfo(address(0x1));
    //     uint256 _reward = 100 * pool.rewardPerBlock();
    //     uint256 accTokenPerShare = (_reward * pool.PRECISION_FACTOR()) / amount;

    //     uint256 pending = pool.pendingReward(address(0x1));
    //     assertEq(pending, amount * accTokenPerShare / pool.PRECISION_FACTOR());

    //     uint256 performanceFee = pool.performanceFee();

    //     vm.deal(address(0x1), 1 ether);
    //     vm.startPrank(address(0x1));

    //     uint256 tokenBal = stakingToken.balanceOf(address(0x1));

    //     vm.expectEmit(true, true, true, true);
    //     emit Claim(address(0x1), pending);
    //     pool.claimReward{value: performanceFee}();

    //     vm.stopPrank();

    //     assertEq(stakingToken.balanceOf(address(0x1)), tokenBal + pending);
    //     assertEq(dividendToken.balanceOf(address(0x1)), 0);

    //     assertEq(pool.availableDividendTokens(), 0.1 ether);
    //     assertEq(pool.availableRewardTokens(), rewards - pending);
    //     assertEq(pool.paidRewards(), pending);
    // }

    // function test_availableRewardTokens() public {
    //     uint256 oldBalance = pool.availableRewardTokens();
    //     rewardToken.mint(address(pool), 10 ether);
    //     assertEq(pool.availableRewardTokens(), oldBalance + 10 ether);
    // }

    // function test_availableRewardTokensInSameRewardAndDividend() public {
    //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 address(stakingToken),
    //                 address(rewardToken),
    //                 address(rewardToken),
    //                 365,
    //                 1 ether,
    //                 DEPOSIT_FEE,
    //                 WITHDRAW_FEE,
    //                 false
    //             )
    //         )
    //     );
    //     uint256 oldBalance = _pool.availableRewardTokens();
    //     rewardToken.mint(address(_pool), 10 ether);
    //     assertEq(_pool.availableRewardTokens(), oldBalance);
    // }

    // function test_availableDividendTokens() public {
    //     assertEq(pool.availableDividendTokens(), 0);

    //     dividendToken.mint(address(pool), 1 ether);
    //     assertEq(pool.availableDividendTokens(), 1 ether);
    // }

    // function test_availableDividendTokensInSameRewardAndDividend() public {
    //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 address(stakingToken),
    //                 address(rewardToken),
    //                 address(rewardToken),
    //                 365,
    //                 1 ether,
    //                 DEPOSIT_FEE,
    //                 WITHDRAW_FEE,
    //                 false
    //             )
    //         )
    //     );
    //     assertEq(_pool.availableDividendTokens(), 0);

    //     rewardToken.mint(address(_pool), 1 ether);
    //     assertEq(_pool.availableDividendTokens(), 1 ether);
    // }

    // function test_insufficientRewards() public {
    //     uint256 remainRewards = pool.availableRewardTokens() + pool.paidRewards();

    //     vm.startPrank(pool.owner());
    //     pool.updateRewardPerBlock(pool.rewardPerBlock() + 0.1 ether);
    //     vm.stopPrank();

    //     uint256 expectedRewards = pool.rewardPerBlock() * (pool.bonusEndBlock() - block.number);
    //     assertEq(pool.insufficientRewards(), expectedRewards - remainRewards);

    //     rewardToken.mint(address(pool), pool.insufficientRewards() - 10000);
    //     assertEq(pool.insufficientRewards(), 10000);

    //     vm.startPrank(pool.operator());
    //     rewardToken.mint(pool.operator(), 10000);
    //     rewardToken.approve(address(pool), 10000);
    //     pool.depositRewards(10000);
    //     assertEq(pool.insufficientRewards(), 0);
    //     vm.stopPrank();
    // }

    // function test_startReward() public {
    //     vm.startPrank(pool.owner());
    //     vm.expectRevert("Pool was already started");
    //     pool.startReward();
    //     vm.stopPrank();

    //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 IERC20(BREWLABS), rewardToken, address(dividendToken), 365, 1 ether, DEPOSIT_FEE, WITHDRAW_FEE, true
    //             )
    //         )
    //     );
    //     rewardToken.mint(address(_pool), _pool.insufficientRewards());

    //     uint256 startBlock = block.number + 100;
    //     uint256 bonusEndBlock = startBlock + 365 * BLOCKS_PER_DAY;

    //     vm.expectEmit(true, true, true, true);
    //     emit NewStartAndEndBlocks(startBlock, bonusEndBlock);
    //     _pool.startReward();
    // }

    // function testFailed_startRewardInInsufficientRewards() public {
    //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 IERC20(BREWLABS), rewardToken, address(dividendToken), 365, 1 ether, DEPOSIT_FEE, WITHDRAW_FEE, true
    //             )
    //         )
    //     );
    //     rewardToken.mint(address(_pool), _pool.insufficientRewards() - 10000);

    //     _pool.startReward();
    // }

    // function test_stopReward() public {
    //     vm.startPrank(pool.operator());
    //     vm.expectEmit(true, true, true, true);
    //     emit RewardsStop(block.number);
    //     pool.stopReward();
    //     vm.stopPrank();
    // }

    // function test_updateEndBlock() public {
    //     uint256 endBlock = pool.bonusEndBlock();
    //     vm.expectRevert("Caller is not owner or operator");
    //     pool.updateEndBlock(endBlock - 1);

    //     vm.startPrank(pool.operator());
    //     vm.expectEmit(true, true, true, true);
    //     emit EndBlockChanged(endBlock - 1);
    //     pool.updateEndBlock(endBlock - 1);
    //     vm.stopPrank();

    //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 IERC20(BREWLABS), rewardToken, address(dividendToken), 365, 1 ether, DEPOSIT_FEE, WITHDRAW_FEE, true
    //             )
    //         )
    //     );
    //     vm.expectRevert("Pool is not started");
    //     _pool.updateEndBlock(block.number + 100000);
    // }

    // function testFailed_updateEndBlockInWrongBlock() public {
    //     utils.mineBlocks(100);

    //     vm.startPrank(pool.operator());
    //     pool.updateEndBlock(block.number - 1);
    //     vm.stopPrank();
    // }

    // function testFailed_updateEndBlockWithPrevBlockOfStartBlock() public {
    //     BrewlabsLockupImpl _pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 IERC20(BREWLABS), rewardToken, address(dividendToken), 365, 1 ether, DEPOSIT_FEE, WITHDRAW_FEE, true
    //             )
    //         )
    //     );
    //     rewardToken.mint(address(_pool), _pool.insufficientRewards());

    //     _pool.startReward();
    //     utils.mineBlocks(10);

    //     pool.updateEndBlock(block.number + 2);
    // }

    // function test_updateRewardPerBlock() public {
    //     vm.startPrank(pool.operator());

    //     vm.expectEmit(true, true, true, true);
    //     emit NewRewardPerBlock(1.1 ether);
    //     pool.updateRewardPerBlock(1.1 ether);

    //     vm.stopPrank();
    // }

    // function test_setServiceInfo() public {
    //     vm.expectRevert("setServiceInfo: FORBIDDEN");
    //     pool.setServiceInfo(address(0x555), 10);

    //     vm.startPrank(pool.treasury());

    //     vm.expectRevert("Invalid address");
    //     pool.setServiceInfo(address(0), 200);

    //     vm.expectEmit(true, true, true, true);
    //     emit ServiceInfoChanged(address(0x555), 10);
    //     pool.setServiceInfo(address(0x555), 10);

    //     vm.stopPrank();
    // }

    // function test_depositRewards() public {
    //     uint256 rewards = pool.availableRewardTokens();

    //     vm.startPrank(pool.owner());

    //     rewardToken.mint(pool.owner(), 100 ether);
    //     rewardToken.approve(address(pool), 100 ether);

    //     pool.depositRewards(100 ether);
    //     assertEq(rewardToken.balanceOf(address(pool)), rewards + 100 ether);
    //     assertEq(pool.availableRewardTokens(), rewards + 100 ether);

    //     vm.expectRevert("invalid amount");
    //     pool.depositRewards(0);
    //     vm.stopPrank();
    // }

    // function test_increaseEmissionRate() public {
    //     uint256 rewards = pool.availableRewardTokens();
    //     uint256 amount = 100 ether;

    //     utils.mineBlocks(100);

    //     vm.startPrank(pool.owner());

    //     rewardToken.mint(pool.owner(), amount);
    //     rewardToken.approve(address(pool), amount);

    //     uint256 remainBlocks = pool.bonusEndBlock() - block.number;

    //     vm.expectEmit(true, false, false, true);
    //     emit NewRewardPerBlock((amount + rewards) / remainBlocks);
    //     pool.increaseEmissionRate(amount);
    //     assertEq(pool.rewardPerBlock(), (amount + rewards) / remainBlocks);

    //     vm.expectRevert("invalid amount");
    //     pool.increaseEmissionRate(0);

    //     vm.roll(pool.bonusEndBlock() + 1);
    //     vm.expectRevert("pool was already finished");
    //     pool.increaseEmissionRate(100);
    //     vm.stopPrank();
    // }

    // function test_emergencyRewardWithdraw() public {
    //     rewardToken.mint(address(pool), 100 ether);

    //     vm.startPrank(pool.owner());

    //     vm.expectRevert("Pool is running");
    //     pool.emergencyRewardWithdraw(10 ether);

    //     uint256 rewards = pool.availableRewardTokens();
    //     vm.roll(pool.bonusEndBlock() + 1);

    //     vm.expectRevert("Insufficient reward tokens");
    //     pool.emergencyRewardWithdraw(rewards + 10 ether);

    //     pool.emergencyRewardWithdraw(10 ether);
    //     assertEq(rewardToken.balanceOf(pool.owner()), 10 ether);

    //     pool.emergencyRewardWithdraw(0);
    //     assertEq(pool.availableRewardTokens(), 0);

    //     vm.stopPrank();
    // }

    // function test_rescueTokens() public {
    //     rewardToken = new MockErc20(18);

    //     pool = BrewlabsLockupImpl(
    //         payable(
    //             factory.createBrewlabsSinglePool(
    //                 address(stakingToken),
    //                 address(rewardToken),
    //                 address(dividendToken),
    //                 365,
    //                 1 ether,
    //                 DEPOSIT_FEE,
    //                 WITHDRAW_FEE,
    //                 true
    //             )
    //         )
    //     );
    //     rewardToken.mint(address(pool), pool.insufficientRewards());
    //     pool.startReward();

    //     vm.startPrank(pool.owner());

    //     vm.expectRevert("Cannot be reward token");
    //     pool.rescueTokens(address(rewardToken), 100);

    //     vm.expectRevert("Insufficient balance");
    //     pool.rescueTokens(address(stakingToken), 100);

    //     stakingToken.mint(address(pool), 1 ether);
    //     vm.expectEmit(true, true, true, true);
    //     emit AdminTokenRecovered(address(stakingToken), 1 ether);
    //     pool.rescueTokens(address(stakingToken), 1 ether);

    //     MockErc20 _token = new MockErc20(18);

    //     _token.mint(address(pool), 1 ether);
    //     pool.rescueTokens(address(_token), 1 ether);
    //     assertEq(_token.balanceOf(address(pool)), 0);
    //     assertEq(_token.balanceOf(address(pool.owner())), 1 ether);

    //     uint256 ownerBalance = address(pool.owner()).balance;

    //     vm.deal(address(pool), 0.5 ether);
    //     pool.rescueTokens(address(0x0), 0.5 ether);
    //     assertEq(address(pool).balance, 0);
    //     assertEq(address(pool.owner()).balance, ownerBalance + 0.5 ether);

    //     vm.stopPrank();
    // }

    // function test_setSwapAggregator() public {
    //     vm.startPrank(pool.owner());

    //     vm.expectRevert("Invalid address");
    //     pool.setSwapAggregator(address(0x0));

    //     vm.expectRevert();
    //     pool.setSwapAggregator(BREWLABS);

    //     address aggregator = address(pool.swapAggregator());

    //     vm.expectEmit(true, true, true, true);
    //     emit SetSwapAggregator(aggregator);
    //     pool.setSwapAggregator(aggregator);

    //     vm.stopPrank();
    // }

    receive() external payable {}
}
