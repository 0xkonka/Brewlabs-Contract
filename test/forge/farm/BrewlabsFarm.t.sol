// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// import "forge-std/console.sol";       // use like hardhat console.log
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {BrewlabsFarm, IERC20} from "../../../contracts/farm/BrewlabsFarm.sol";
import {Utils} from "../utils/Utils.sol";

contract BrewlabsFarmBase is Test {
    MockErc20 internal token;
    MockErc20 internal reflectionToken;
    MockErc20 internal lpToken;
    Utils internal utils;

    BrewlabsFarm internal farm;

    uint256 internal BLOCKS_PER_DAY = 28800;
    uint16 internal DEPOSIT_FEE = 10;
    uint16 internal WITHDRAW_FEE = 20;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetBuyBackWallet(address indexed user, address newAddress);
    event SetPerformanceFee(uint256 fee);
    event SetRewardFee(uint256 fee);
    event UpdateEmissionRate(address indexed user, uint256 rewardPerBlock);

    receive() external payable {}
}

contract BrewlabsFarmTest is BrewlabsFarmBase {
    function setUp() public {
        token = new MockErc20(18);
        reflectionToken = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsFarm(IERC20(token), address(reflectionToken), 1e18, true);
        farm.add(1000, IERC20(lpToken), DEPOSIT_FEE, WITHDRAW_FEE, 365, false);
    }

    function tryDeposit(address _user, uint256 _pid, uint256 _amount) internal {
        lpToken.mint(_user, _amount);
        vm.deal(_user, farm.performanceFee());

        vm.startPrank(_user);
        lpToken.approve(address(farm), _amount);

        uint256 _depositFee = _amount * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, _pid, _amount - _depositFee);
        farm.deposit{value: farm.performanceFee()}(_pid, _amount);
        vm.stopPrank();
    }

    function test_firstDeposit() public {
        uint256 treasuryVal = address(farm.treasury()).balance;
        tryDeposit(address(0x1), 0, 1 ether);

        (uint256 amount, uint256 rewardDebt, uint256 reflectionDebt) = farm.userInfo(0, address(0x1));

        uint256 _depositFee = 1 ether * DEPOSIT_FEE / 10000;
        assertEq(amount, 1 ether - _depositFee);
        assertEq(lpToken.balanceOf(farm.feeAddress()), _depositFee);
        assertEq(rewardDebt, 0);
        assertEq(reflectionDebt, 0);
        assertEq(address(farm.treasury()).balance - treasuryVal, farm.performanceFee());

        vm.expectRevert(abi.encodePacked("should pay small gas"));
        farm.deposit(0, 0);
    }

    function test_notFirstDeposit() public {
        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);
        reflectionToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0, 1 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(0, address(0x1));
        uint256 pendingReflection = farm.pendingReflections(0, address(0x1));

        tryDeposit(address(0x1), 0, 1 ether);
        assertEq(token.balanceOf(address(0x1)), pending);
        assertEq(reflectionToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards - pending);
    }

    function test_depositAfterStakingIsFinished() public {
        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);
        reflectionToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0, 1 ether);

        (,,,, uint256 bonusEndBlock,,,,,,) = farm.poolInfo(0);
        vm.roll(bonusEndBlock + 10);

        lpToken.mint(address(0x1), 0.1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 0.1 ether);

        vm.expectEmit(true, false, false, true);
        emit UpdateEmissionRate(address(0x1), 0);
        farm.deposit{value: farm.performanceFee()}(0, 0.1 ether);
        vm.stopPrank();
    }

    function test_depositWhenRewardFeeIsGtZero() public {
        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);
        reflectionToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0, 1 ether);
        tryDeposit(address(0x2), 0, 1.2 ether);

        uint256 rewardFee = 100;
        vm.startPrank(farm.owner());
        farm.setRewardFee(rewardFee);
        vm.stopPrank();

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(0, address(0x1));
        uint256 pendingReflection = farm.pendingReflections(0, address(0x1));

        lpToken.mint(address(0x1), 0.1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 0.1 ether);
        (,,,, uint256 bonusEndBlock,,,,,,) = farm.poolInfo(0);
        uint256 _expectedRewards = rewards - farm.rewardPerBlock() * 100;
        _expectedRewards += (pending * rewardFee) / 10000;
        _expectedRewards /= (bonusEndBlock - block.number);

        uint256 _depositFee = 0.1 ether * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(0x1), 0, 0.1 ether - _depositFee);
        vm.expectEmit(true, false, false, true);
        emit UpdateEmissionRate(address(0x1), _expectedRewards);
        farm.deposit{value: farm.performanceFee()}(0, 0.1 ether);

        assertEq(token.balanceOf(address(0x1)), (pending * (10000 - rewardFee)) / 10000);
        assertEq(reflectionToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards - (pending * (10000 - rewardFee)) / 10000);
    }

    function test_fuzzDeposit(uint96[10] memory _amounts) public {
        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);
        reflectionToken.mint(address(farm), 0.1 ether);

        vm.roll(farm.startBlock() + 100);

        address payable[] memory users = utils.createUsers(10);
        for (uint256 i = 0; i < 10; i++) {
            vm.assume(_amounts[i] > 0);
            tryDeposit(users[i], 0, _amounts[i]);

            utils.mineBlocks(10);
        }
    }

    function test_pendingRewards() public {
        tryDeposit(address(0x1), 0, 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 0, 2 ether);

        vm.roll(farm.startBlock() + 1000);

        (,,,, uint256 bonusEndBlock,,,,,,) = farm.poolInfo(0);
        (uint256 amount,,) = farm.userInfo(0, address(0x1));

        uint256 lpSupply = lpToken.balanceOf(address(farm));
        uint256 multiplier = farm.getMultiplier(farm.startBlock(), block.number, bonusEndBlock);
        uint256 brewsReward = multiplier * farm.rewardPerBlock() * 1000 / farm.totalAllocPoint();
        uint256 accTokenPerShare = brewsReward * 1e12 / lpSupply;
        uint256 pending = amount * accTokenPerShare / 1e12;
        assertEq(farm.pendingRewards(0, address(0x1)), pending);

        farm.updatePool(0);

        utils.mineBlocks(100);
        brewsReward = multiplier * farm.rewardPerBlock() * 100 / farm.totalAllocPoint();
        accTokenPerShare += brewsReward * 1e12 / lpSupply;
        pending = amount * accTokenPerShare / 1e12;
        assertEq(farm.pendingRewards(0, address(0x1)), pending);
    }

    function test_pendingReflections() public {
        tryDeposit(address(0x1), 0, 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 0, 2 ether);

        reflectionToken.mint(address(farm), 0.01 ether);

        vm.roll(farm.startBlock() + 1000);
        uint256 lpSupply = lpToken.balanceOf(address(farm));
        uint256 reflectionAmt = farm.availableDividendTokens();
        uint256 _accReflectionPerPoint = reflectionAmt * 1e12 / farm.totalAllocPoint();
        uint256 accReflectionPerShare = 1000 * _accReflectionPerPoint / lpSupply;

        (uint256 amount,,) = farm.userInfo(0, address(0x1));

        uint256 pending = amount * accReflectionPerShare / 1e12;
        assertEq(farm.pendingReflections(0, address(0x1)), pending);
    }

    function test_withdraw() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();
        reflectionToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0, 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 0, 2 ether);

        vm.startPrank(address(0x1));

        uint256 _withdrawFee = 0.1 ether * WITHDRAW_FEE / 10000;
        vm.deal(address(0x1), ethFee);
        farm.withdraw{value: ethFee}(0, 0.1 ether);
        assertEq(lpToken.balanceOf(address(0x1)), 0.1 ether - _withdrawFee);
        assertEq(token.balanceOf(address(0x1)), 0);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(0, address(0x1));
        uint256 pendingReflection = farm.pendingReflections(0, address(0x1));

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Insufficient reward tokens"));
        farm.withdraw{value: ethFee}(0, 0.1 ether);

        token.mint(address(farm), rewards);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(0x1), 0, 0.2 ether);
        farm.withdraw{value: ethFee}(0, 0.2 ether);
        assertEq(token.balanceOf(address(0x1)), pending);
        assertEq(reflectionToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.pendingRewards(0, address(0x1)), 0);
        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards - pending);

        vm.deal(address(0x1), ethFee);

        reflectionToken.mint(address(farm), 0.1 ether);

        (,,,, uint256 bonusEndBlock,,,,,,) = farm.poolInfo(0);
        vm.roll(bonusEndBlock + 10);
        vm.expectEmit(true, false, false, true);
        emit UpdateEmissionRate(address(0x1), 0);
        farm.withdraw{value: ethFee}(0, 0.1 ether);

        vm.expectRevert("should pay small gas");
        farm.withdraw(0, 0.1 ether);

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Amount should be greator than 0"));
        farm.withdraw{value: ethFee}(0, 0);

        vm.expectRevert(abi.encodePacked("withdraw: not good"));
        farm.withdraw{value: ethFee}(0, 1 ether);

        (uint256 amount,,) = farm.userInfo(0, address(0x1));
        farm.withdraw{value: ethFee}(0, amount);
        vm.stopPrank();

        vm.startPrank(address(0x2));
        vm.deal(address(0x2), ethFee);
        (amount,,) = farm.userInfo(0, address(0x2));
        farm.withdraw{value: ethFee}(0, amount);
        vm.stopPrank();
    }

    function test_claimReward() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();

        reflectionToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0, 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 0, 2 ether);

        vm.startPrank(address(0x1));
        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(0, address(0x1));

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Insufficient reward tokens"));
        farm.claimReward{value: ethFee}(0);

        token.mint(address(farm), rewards);
        farm.claimReward{value: ethFee}(0);
        assertEq(token.balanceOf(address(0x1)), pending);

        assertEq(farm.pendingRewards(0, address(0x1)), 0);
        assertEq(farm.availableDividendTokens(), 0.1 ether);
        assertEq(farm.availableRewardTokens(), rewards - pending);

        vm.expectRevert("should pay small gas");
        farm.claimReward(0);

        vm.stopPrank();
    }

    function test_claimDividend() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();

        token.mint(address(farm), rewards);
        reflectionToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0, 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 0, 2 ether);

        vm.startPrank(address(0x1));
        vm.roll(farm.startBlock() + 100);
        uint256 pendingReflection = farm.pendingReflections(0, address(0x1));

        vm.deal(address(0x1), ethFee);
        farm.claimDividend{value: ethFee}(0);
        assertEq(reflectionToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.pendingReflections(0, address(0x1)), 0);
        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards);

        vm.deal(address(0x1), ethFee);
        farm.claimDividend{value: ethFee}(0);
        assertEq(reflectionToken.balanceOf(address(0x1)), pendingReflection);

        vm.expectRevert("should pay small gas");
        farm.claimDividend(0);

        vm.stopPrank();
    }

    function test_updatePool() public {
        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);

        // before start staking
        (,,,,, uint256 lastRewardBlock,,,,,) = farm.poolInfo(0);
        farm.updatePool(0);
        assertGe(lastRewardBlock, block.number);

        vm.roll(farm.startBlock());

        // deposit did not be made yet
        (,,,,, uint256 lastRewardBlock2,,,,,) = farm.poolInfo(0);
        farm.updatePool(0);
        assertEq(lastRewardBlock2, block.number);

        tryDeposit(address(0x1), 0, 1 ether);
        reflectionToken.mint(address(farm), 0.01 ether);
        assertEq(farm.availableDividendTokens(), 0.01 ether);

        uint256 _rewards = farm.rewardPerBlock() * 100;
        uint256 lpSupply = lpToken.balanceOf(address(farm));
        uint256 dShare = _rewards * 1e12 / lpSupply;
        (,,,,,, uint256 prevAccTokenPerShare,,,,) = farm.poolInfo(0);
        utils.mineBlocks(100);

        farm.updatePool(0);

        (,,,,, uint256 _lastRewardBlock, uint256 accTokenPerShare, uint256 accReflectionPerShare,,,) = farm.poolInfo(0);
        assertEq(_lastRewardBlock, block.number);
        assertEq(accTokenPerShare, prevAccTokenPerShare + dShare);
        assertEq(accReflectionPerShare, 0.01 ether * 1e12 / lpSupply);
    }

    function test_massUpdatePools() public {
        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);

        vm.roll(farm.startBlock());

        tryDeposit(address(0x1), 0, 1 ether);
        reflectionToken.mint(address(farm), 0.01 ether);
        assertEq(farm.availableDividendTokens(), 0.01 ether);

        uint256 _rewards = farm.rewardPerBlock() * 100;
        uint256 lpSupply = lpToken.balanceOf(address(farm));
        uint256 dShare = _rewards * 1e12 / lpSupply;
        (,,,,,, uint256 prevAccTokenPerShare,,,,) = farm.poolInfo(0);
        utils.mineBlocks(100);

        farm.massUpdatePools();

        (,,,,, uint256 _lastRewardBlock, uint256 accTokenPerShare, uint256 accReflectionPerShare,,,) = farm.poolInfo(0);
        assertEq(_lastRewardBlock, block.number);
        assertEq(accTokenPerShare, prevAccTokenPerShare + dShare);
        assertEq(accReflectionPerShare, 0.01 ether * 1e12 / lpSupply);
    }

    function test_emergencyWithdrawReflections() public {
        reflectionToken.mint(address(farm), 100 ether);

        farm.emergencyWithdrawReflections();
        assertEq(reflectionToken.balanceOf(farm.owner()), 100 ether);
        assertEq(reflectionToken.balanceOf(address(farm)), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.emergencyWithdrawReflections();
    }

    function test_transferToHarvest() public {
        reflectionToken.mint(address(farm), 100 ether);

        farm.transferToHarvest();
        assertEq(reflectionToken.balanceOf(farm.owner()), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.transferToHarvest();
    }

    function test_availableRewardTokens() public {
        assertEq(farm.availableRewardTokens(), 0);

        token.mint(address(farm), 10 ether);
        assertEq(farm.availableRewardTokens(), 10 ether);
    }

    function test_availableDividendTokens() public {
        assertEq(farm.availableDividendTokens(), 0);

        reflectionToken.mint(address(farm), 1 ether);
        assertEq(farm.availableDividendTokens(), 1 ether);
    }

    function test_insufficientRewards() public {
        uint256 expectedRewards = farm.rewardPerBlock() * 365 * 28800;
        assertEq(farm.insufficientRewards(), expectedRewards);

        token.mint(address(farm), farm.insufficientRewards() - 10000);
        assertEq(farm.insufficientRewards(), 10000);

        vm.startPrank(farm.owner());
        token.mint(farm.owner(), 10000);
        token.approve(address(farm), 10000);
        farm.depositRewards(10000);
        assertEq(farm.insufficientRewards(), 0);
        vm.stopPrank();
    }

    function test_setFeeAddress() public {
        vm.expectEmit(true, true, false, false);
        emit SetFeeAddress(farm.feeAddress(), address(0x1));
        farm.setFeeAddress(address(0x1));
    }

    function testFailed_setFeeAddressInNotOwner() public {
        vm.prank(address(0x2));
        farm.setFeeAddress(address(0x1));
    }

    function test_poolLength() public {
        assertEq(farm.poolLength(), 1);
        farm.add(1000, IERC20(address(0x1)), 10, 20, 365, false);
        assertEq(farm.poolLength(), 2);
    }

    function test_add() public {
        farm.add(100, IERC20(address(0x1)), 10, 100, 180, false);
        assertEq(farm.totalAllocPoint(), 1100);

        (
            IERC20 _lpToken,
            uint256 allocPoint,
            uint256 duration,
            uint256 startBlock,
            uint256 bonusEndBlock,
            uint256 lastRewardBlock,
            ,
            ,
            ,
            uint16 depositFee,
            uint16 withdrawFee
        ) = farm.poolInfo(1);

        assertEq(address(_lpToken), address(0x01));
        assertEq(allocPoint, 100);
        assertEq(duration, 180);
        assertEq(startBlock, farm.startBlock());
        assertEq(bonusEndBlock, farm.startBlock() + duration * BLOCKS_PER_DAY);
        assertEq(lastRewardBlock, farm.startBlock());
        assertEq(depositFee, 10);
        assertEq(withdrawFee, 100);

        vm.expectRevert(abi.encodePacked("nonDuplicated: duplicated"));
        farm.add(100, lpToken, 10, 100, 180, false);
        vm.expectRevert(abi.encodePacked("add: invalid deposit fee basis points"));
        farm.add(100, IERC20(address(0x2)), 11000, 10, 180, false);
        vm.expectRevert(abi.encodePacked("add: invalid withdraw fee basis points"));
        farm.add(100, IERC20(address(0x2)), 10, 11000, 180, false);
    }

    function test_set() public {
        farm.set(0, 2000, 10, 100, 500, true);
        assertEq(farm.totalAllocPoint(), 2000);

        (
            IERC20 _lpToken,
            uint256 allocPoint,
            uint256 duration,
            uint256 startBlock,
            uint256 bonusEndBlock,
            uint256 lastRewardBlock,
            ,
            ,
            ,
            uint16 depositFee,
            uint16 withdrawFee
        ) = farm.poolInfo(0);

        assertEq(address(_lpToken), address(lpToken));
        assertEq(allocPoint, 2000);
        assertEq(duration, 500);
        assertEq(startBlock, farm.startBlock());
        assertEq(bonusEndBlock, farm.startBlock() + duration * BLOCKS_PER_DAY);
        assertEq(lastRewardBlock, farm.startBlock());
        assertEq(depositFee, 10);
        assertEq(withdrawFee, 100);

        vm.expectRevert(abi.encodePacked("set: invalid deposit fee basis points"));
        farm.set(0, 1000, 11000, 10, 180, false);
        vm.expectRevert(abi.encodePacked("set: invalid withdraw fee basis points"));
        farm.set(0, 1000, 10, 11000, 180, false);

        vm.roll(startBlock + 100 * BLOCKS_PER_DAY + 1);
        vm.expectRevert(abi.encodePacked("set: invalid duration"));
        farm.set(0, 1000, 10, 20, 100, false);
    }

    function test_swapSetting() public {
        address[] memory path;
        farm.setSwapSetting(0, address(0x1), path, path, path, path, true);
    }

    function test_getMultiplier() public {
        uint256 multiplier = farm.getMultiplier(100, 1000, 90);
        assertEq(multiplier, 0);

        multiplier = farm.getMultiplier(100, 1000, 500);
        assertEq(multiplier, 400);

        multiplier = farm.getMultiplier(100, 1000, 2000);
        assertEq(multiplier, 900);
    }

    function test_setPerformanceFee() public {
        vm.startPrank(farm.treasury());
        vm.expectEmit(false, false, false, true);
        emit SetPerformanceFee(100);
        farm.setPerformanceFee(100);
        vm.stopPrank();

        vm.expectRevert(abi.encodePacked("setPerformanceFee: FORBIDDEN"));
        farm.setPerformanceFee(200);
    }

    function test_setRewardFee() public {
        vm.expectEmit(false, false, false, true);
        emit SetRewardFee(100);
        farm.setRewardFee(100);

        vm.expectRevert(abi.encodePacked("setRewardFee: invalid percentage"));
        farm.setRewardFee(10000);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.setRewardFee(101);
    }

    function test_setBuyBackWallet() public {
        vm.startPrank(farm.treasury());
        vm.expectEmit(true, false, false, false);
        emit SetBuyBackWallet(farm.treasury(), address(0x1));
        farm.setBuyBackWallet(address(0x1));
        vm.stopPrank();

        vm.expectRevert(abi.encodePacked("setBuyBackWallet: FORBIDDEN"));
        farm.setBuyBackWallet(address(0x2));
    }

    function test_updateEmissionRate() public {
        vm.expectEmit(false, false, false, true);
        emit UpdateEmissionRate(farm.owner(), 1e9);
        farm.updateEmissionRate(1e9);

        assertEq(farm.rewardPerBlock(), 1e9);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.updateEmissionRate(111);
    }

    function test_updateStartBlock() public {
        farm.updateStartBlock(block.number + 1000);
        assertEq(farm.startBlock(), block.number + 1000);

        (,, uint256 duration, uint256 startBlock, uint256 bonusEndBlock,,,,,,) = farm.poolInfo(0);
        assertEq(startBlock, block.number + 1000);
        assertEq(bonusEndBlock, block.number + 1000 + BLOCKS_PER_DAY * duration);

        vm.roll(farm.startBlock() + 10);
        vm.expectRevert(abi.encodePacked("farm is running now"));
        farm.updateStartBlock(100);

        vm.roll(100);
        vm.expectRevert(abi.encodePacked("should be greater than current block"));
        farm.updateStartBlock(block.number - 1);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.updateStartBlock(111);
    }

    function test_depositRewards() public {
        token.mint(address(0x1), 100 ether);

        vm.startPrank(address(0x1));
        token.approve(address(farm), 100 ether);
        vm.stopPrank();

        vm.prank(address(0x1));
        farm.depositRewards(100 ether);
        assertEq(token.balanceOf(address(farm)), 100 ether);
        assertEq(farm.availableRewardTokens(), 100 ether);

        vm.expectRevert(abi.encodePacked(""));
        farm.depositRewards(0);
    }

    function test_increaseEmissionRate() public {
        uint256 amount = farm.insufficientRewards();
        amount += 100 ether;

        token.mint(farm.owner(), amount);
        token.approve(address(farm), amount);

        vm.roll(farm.startBlock());
        vm.expectEmit(true, false, false, true);
        emit UpdateEmissionRate(farm.owner(), amount / BLOCKS_PER_DAY / 365);
        farm.increaseEmissionRate(amount);
        assertEq(farm.rewardPerBlock(), amount / BLOCKS_PER_DAY / 365);

        vm.expectRevert(abi.encodePacked("invalid amount"));
        farm.increaseEmissionRate(0);

        vm.roll(farm.startBlock() + BLOCKS_PER_DAY * 365 + 1);
        vm.expectRevert(abi.encodePacked("pool was already finished"));
        farm.increaseEmissionRate(100);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.increaseEmissionRate(111);
    }

    function test_emergencyWithdrawRewards() public {
        token.mint(address(farm), 100 ether);

        farm.emergencyWithdrawRewards(10 ether);
        assertEq(token.balanceOf(farm.owner()), 10 ether);

        farm.emergencyWithdrawRewards(0);
        assertEq(token.balanceOf(address(farm)), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.emergencyWithdrawRewards(111);
    }

    function test_recoverWrongToken() public {
        vm.expectRevert(abi.encodePacked("cannot recover reward token or reflection token"));
        farm.recoverWrongToken(address(token));

        vm.expectRevert(abi.encodePacked("cannot recover reward token or reflection token"));
        farm.recoverWrongToken(address(reflectionToken));

        vm.expectRevert(abi.encodePacked("token is using on pool"));
        farm.recoverWrongToken(address(lpToken));

        MockErc20 _token = new MockErc20(18);

        _token.mint(address(farm), 1 ether);
        farm.recoverWrongToken(address(_token));
        assertEq(_token.balanceOf(address(farm)), 0);
        assertEq(_token.balanceOf(address(farm.owner())), 1 ether);

        uint256 ownerBalance = address(farm.owner()).balance;

        vm.deal(address(farm), 0.5 ether);
        farm.recoverWrongToken(address(0x0));
        assertEq(address(farm).balance, 0);
        assertEq(address(farm.owner()).balance, ownerBalance + 0.5 ether);
    }
}

contract BrewlabsFarmWithSameTest is BrewlabsFarmBase {
    function setUp() public {
        token = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsFarm(IERC20(token), address(token), 1e18, true);
        farm.add(1000, IERC20(lpToken), DEPOSIT_FEE, WITHDRAW_FEE, 365, false);
    }

    function test_availableRewardTokens() public {
        token.mint(address(farm), 1 ether);
        assertEq(farm.availableRewardTokens(), 0 ether);
        assertEq(farm.availableDividendTokens(), 1 ether);

        token.mint(farm.owner(), 10 ether);

        vm.startPrank(farm.owner());
        token.approve(address(farm), 10 ether);
        farm.depositRewards(10 ether);
        assertEq(farm.availableRewardTokens(), 10 ether);
        assertEq(farm.availableDividendTokens(), 1 ether);

        vm.stopPrank();
    }
}

contract BrewlabsFarmWithETHReflectionTest is BrewlabsFarmBase {
    function setUp() public {
        token = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsFarm(IERC20(token), address(0x0), 1e18, true);
        farm.add(1000, IERC20(lpToken), DEPOSIT_FEE, WITHDRAW_FEE, 365, false);
    }

    function tryDeposit(address _user, uint256 _pid, uint256 _amount) internal {
        lpToken.mint(_user, _amount);
        vm.deal(_user, farm.performanceFee());

        vm.startPrank(_user);
        lpToken.approve(address(farm), _amount);

        uint256 _depositFee = _amount * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, _pid, _amount - _depositFee);
        farm.deposit{value: farm.performanceFee()}(_pid, _amount);
        vm.stopPrank();
    }

    function test_availableDividendTokens() public {
        vm.deal(address(farm), 0.01 ether);
        assertEq(farm.availableDividendTokens(), 0.01 ether);
    }

    function test_emergencyWithdrawReflections() public {
        vm.deal(address(farm), 0.01 ether);

        farm.emergencyWithdrawReflections();
        uint256 ethBalance = address(farm.owner()).balance;
        assertEq(address(farm).balance, 0);
        assertGe(address(farm.owner()).balance, ethBalance);
    }

    function test_deposit() public {
        address payable _user = utils.getNextUserAddress();

        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);

        tryDeposit(address(_user), 0, 1 ether);
        vm.deal(address(farm), 0.01 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(0, address(_user));
        uint256 pendingReflection = farm.pendingReflections(0, address(_user));
        tryDeposit(address(_user), 0, 1 ether);
        assertEq(token.balanceOf(address(_user)), pending);
        assertEq(address(_user).balance, pendingReflection);
    }

    function test_withdraw() public {
        address payable _user = utils.getNextUserAddress();

        uint256 rewards = farm.insufficientRewards();
        token.mint(address(farm), rewards);

        tryDeposit(address(_user), 0, 1 ether);
        vm.deal(address(farm), 0.01 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(0, address(_user));
        uint256 pendingReflection = farm.pendingReflections(0, address(_user));

        vm.startPrank(_user);

        uint256 ethFee = farm.performanceFee();
        vm.deal(_user, ethFee);
        farm.withdraw{value: ethFee}(0, 0.1 ether);
        assertEq(token.balanceOf(address(_user)), pending);
        assertEq(address(_user).balance, pendingReflection);
    }

    function test_claimDividend() public {
        address payable _user = utils.getNextUserAddress();

        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();

        token.mint(address(farm), rewards);

        tryDeposit(address(_user), 0, 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 0, 2 ether);

        vm.deal(address(farm), 0.1 ether);
        assertEq(farm.availableDividendTokens(), 0.1 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pendingReflection = farm.pendingReflections(0, address(_user));
        vm.deal(address(_user), ethFee);

        vm.startPrank(address(_user));
        farm.claimDividend{value: ethFee}(0);
        assertEq(address(_user).balance, pendingReflection);
        vm.stopPrank();
    }
}
