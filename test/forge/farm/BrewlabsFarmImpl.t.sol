// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {BrewlabsFarmImpl, IERC20} from "../../../contracts/farm/BrewlabsFarmImpl.sol";
import {Utils} from "../utils/Utils.sol";

contract BrewlabsFarmImplBase is Test {
    MockErc20 internal rewardToken;
    MockErc20 internal dividendToken;
    MockErc20 internal lpToken;
    Utils internal utils;

    BrewlabsFarmImpl internal farm;

    uint256 internal BLOCKS_PER_DAY = 28800;
    uint16 internal DEPOSIT_FEE = 10;
    uint16 internal WITHDRAW_FEE = 20;

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
    event EndBlockUpdated(uint256 blockNumber);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event DurationUpdated(uint256 duration);
    event SetAutoAdjustableForRewardRate(bool status);
    event SetRewardFee(uint256 fee);
    event OperatorTransferred(address oldOperator, address newOperator);
    event SetSettings(uint256 depositFee, uint256 withdrawFee, address feeAddr);

    receive() external payable {}
}

contract BrewlabsFarmImplTest is BrewlabsFarmImplBase {
    function setUp() public {
        rewardToken = new MockErc20(18);
        dividendToken = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsFarmImpl();
        farm.initialize(
            lpToken,
            rewardToken,
            address(dividendToken),
            1e18,
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            true,
            farm.owner(),
            farm.owner()
        );

        farm.startReward();
        utils.mineBlocks(101);
    }

    function test_depositInNotStartedPool() public {
        BrewlabsFarmImpl _farm = new BrewlabsFarmImpl();
        _farm.initialize(
            lpToken,
            rewardToken,
            address(dividendToken),
            1e18,
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            true,
            _farm.owner(),
            _farm.owner()
        );

        address _user = address(0x1);
        lpToken.mint(_user, 1 ether);
        vm.deal(_user, _farm.performanceFee());

        vm.startPrank(_user);
        lpToken.approve(address(_farm), 1 ether);

        uint256 performanceFee = _farm.performanceFee();
        vm.expectRevert(abi.encodePacked("Farming hasn't started yet"));
        _farm.deposit{value: performanceFee}(1 ether);
        vm.stopPrank();

        _farm.startReward();
        utils.mineBlocks(99);

        vm.startPrank(_user);
        vm.expectRevert(abi.encodePacked("Farming hasn't started yet"));
        _farm.deposit{value: performanceFee}(1 ether);
        vm.stopPrank();
    }

    function tryDeposit(address _user, uint256 _amount) internal {
        lpToken.mint(_user, _amount);
        vm.deal(_user, farm.performanceFee());

        vm.startPrank(_user);
        lpToken.approve(address(farm), _amount);

        uint256 _depositFee = _amount * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, _amount - _depositFee);
        farm.deposit{value: farm.performanceFee()}(_amount);
        vm.stopPrank();
    }

    function test_firstDeposit() public {
        uint256 treasuryVal = address(farm.treasury()).balance;
        tryDeposit(address(0x1), 1 ether);

        (uint256 amount, uint256 rewardDebt, uint256 reflectionDebt) = farm.userInfo(address(0x1));

        uint256 _depositFee = 1 ether * DEPOSIT_FEE / 10000;
        assertEq(amount, 1 ether - _depositFee);
        assertEq(lpToken.balanceOf(farm.feeAddress()), _depositFee);
        assertEq(rewardDebt, 0);
        assertEq(reflectionDebt, 0);
        assertEq(address(farm.treasury()).balance - treasuryVal, farm.performanceFee());

        vm.expectRevert(abi.encodePacked("Amount should be greator than 0"));
        farm.deposit(0);

        lpToken.mint(address(0x1), 1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 1 ether);
        vm.expectRevert(abi.encodePacked("should pay small gas to compound or harvest"));
        farm.deposit(1 ether);
    }

    function test_notFirstDeposit() public {
        uint256 rewards = farm.insufficientRewards();
        rewardToken.mint(address(farm), rewards);
        dividendToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 1 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(address(0x1));
        uint256 pendingReflection = farm.pendingReflections(address(0x1));

        tryDeposit(address(0x1), 1 ether);
        assertEq(rewardToken.balanceOf(address(0x1)), pending);
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards - pending);
    }

    function test_depositAfterStakingIsFinished() public {
        uint256 rewards = farm.insufficientRewards();
        rewardToken.mint(address(farm), rewards);
        dividendToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 1 ether);

        uint256 bonusEndBlock = farm.bonusEndBlock();
        vm.roll(bonusEndBlock + 10);

        lpToken.mint(address(0x1), 0.1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 0.1 ether);

        farm.deposit{value: farm.performanceFee()}(0.1 ether);
        vm.stopPrank();
    }

    function test_depositWhenRewardFeeIsGtZero() public {
        uint256 rewards = farm.insufficientRewards();
        rewardToken.mint(address(farm), rewards);
        dividendToken.mint(address(farm), 0.1 ether);
        tryDeposit(address(0x1), 1 ether);
        tryDeposit(address(0x2), 1.2 ether);

        uint256 rewardFee = 100;
        vm.startPrank(farm.owner());
        farm.setRewardFee(rewardFee);
        vm.stopPrank();

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(address(0x1));
        uint256 pendingReflection = farm.pendingReflections(address(0x1));

        lpToken.mint(address(0x1), 0.1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 0.1 ether);
        uint256 bonusEndBlock = farm.bonusEndBlock();
        uint256 remainRewards = rewards;
        uint256 shouldTotalPaid = farm.rewardPerBlock() * (block.number - farm.lastRewardBlock());
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid + (pending - (pending * (10000 - rewardFee)) / 10000);
        }
        uint256 _expectedRewards = remainRewards / (bonusEndBlock - block.number);

        uint256 _depositFee = 0.1 ether * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(0x1), 0.1 ether - _depositFee);
        vm.expectEmit(false, false, false, true);
        emit NewRewardPerBlock(_expectedRewards);
        farm.deposit{value: farm.performanceFee()}(0.1 ether);

        assertEq(rewardToken.balanceOf(address(0x1)), (pending * (10000 - rewardFee)) / 10000);
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards - (pending * (10000 - rewardFee)) / 10000);
    }

    function test_fuzzDeposit(uint96[10] memory _amounts) public {
        uint256 rewards = farm.insufficientRewards();
        rewardToken.mint(address(farm), rewards);
        dividendToken.mint(address(farm), 0.1 ether);

        vm.roll(farm.startBlock() + 100);

        address payable[] memory users = utils.createUsers(10);
        for (uint256 i = 0; i < 10; i++) {
            vm.assume(_amounts[i] > 0);
            tryDeposit(users[i], _amounts[i]);

            utils.mineBlocks(10);
        }
    }

    function test_pendingRewards() public {
        tryDeposit(address(0x1), 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        utils.mineBlocks(1000);

        (uint256 amount, uint256 rewardDebt,) = farm.userInfo(address(0x1));

        uint256 rewards = 1000 * farm.rewardPerBlock();
        uint256 accTokenPerShare = farm.accTokenPerShare() + rewards * 1e18 / farm.totalStaked();
        uint256 pending = amount * accTokenPerShare / 1e18 - rewardDebt;
        assertEq(farm.pendingRewards(address(0x1)), pending);

        utils.mineBlocks(100);
        rewards = 1100 * farm.rewardPerBlock();
        accTokenPerShare = farm.accTokenPerShare() + rewards * 1e18 / farm.totalStaked();
        pending = amount * accTokenPerShare / 1e18;
        assertEq(farm.pendingRewards(address(0x1)), pending);
    }

    function test_pendingReflections() public {
        tryDeposit(address(0x1), 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        dividendToken.mint(address(farm), 0.01 ether);

        utils.mineBlocks(1000);
        uint256 reflectionAmt = farm.availableDividendTokens();
        uint256 accReflectionPerShare = reflectionAmt * 1e18 / farm.totalStaked();

        (uint256 amount,,) = farm.userInfo(address(0x1));

        uint256 pending = amount * accReflectionPerShare / 1e18;
        assertEq(farm.pendingReflections(address(0x1)), pending);
    }

    function test_withdraw() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();
        dividendToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        (uint256 amount,,) = farm.userInfo(address(0x1));
        uint256 _withdrawFee = amount * WITHDRAW_FEE / 10000;
        uint256 pending = farm.pendingRewards(address(0x1));
        uint256 pendingReflection = farm.pendingReflections(address(0x1));

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Amount to withdraw too high"));
        farm.withdraw{value: ethFee}(amount + 10);

        vm.startPrank(address(0x1));
        vm.expectRevert(abi.encodePacked("Insufficient reward tokens"));
        farm.withdraw{value: ethFee}(amount);
        vm.stopPrank();

        rewardToken.mint(address(farm), rewards);

        vm.startPrank(address(0x1));
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(0x1), amount);
        farm.withdraw{value: ethFee}(amount);
        assertEq(rewardToken.balanceOf(address(0x1)), pending);
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);
        assertEq(lpToken.balanceOf(address(0x1)), amount - _withdrawFee);

        assertEq(farm.pendingRewards(address(0x1)), 0);
        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards - pending);
        vm.stopPrank();

        vm.deal(address(0x1), ethFee);

        dividendToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 0.1 ether);
        utils.mineBlocks(100);

        vm.startPrank(address(0x1));
        vm.expectRevert("should pay small gas to compound or harvest");
        farm.withdraw(0.001 ether);

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Amount should be greator than 0"));
        farm.withdraw{value: ethFee}(0);

        (amount,,) = farm.userInfo(address(0x1));
        farm.withdraw{value: ethFee}(amount);
        vm.stopPrank();

        vm.startPrank(address(0x2));
        vm.deal(address(0x2), ethFee);
        (amount,,) = farm.userInfo(address(0x2));
        farm.withdraw{value: ethFee}(amount);
        vm.stopPrank();
    }

    function test_claimReward() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();

        dividendToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        vm.startPrank(address(0x1));
        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(address(0x1));

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Insufficient reward tokens"));
        farm.claimReward{value: ethFee}();

        rewardToken.mint(address(farm), rewards);
        farm.claimReward{value: ethFee}();
        assertEq(rewardToken.balanceOf(address(0x1)), pending);

        assertEq(farm.pendingRewards(address(0x1)), 0);
        assertEq(farm.availableDividendTokens(), 0.1 ether);
        assertEq(farm.availableRewardTokens(), rewards - pending);

        vm.expectRevert("should pay small gas to compound or harvest");
        farm.claimReward();

        vm.stopPrank();
    }

    function test_claimDividend() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();

        rewardToken.mint(address(farm), rewards);
        dividendToken.mint(address(farm), 0.1 ether);

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        vm.startPrank(address(0x1));
        vm.roll(farm.startBlock() + 100);
        uint256 pendingReflection = farm.pendingReflections(address(0x1));

        vm.deal(address(0x1), ethFee);
        farm.claimDividend{value: ethFee}();
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        assertEq(farm.pendingReflections(address(0x1)), 0);
        assertEq(farm.availableDividendTokens(), 0.1 ether - pendingReflection);
        assertEq(farm.availableRewardTokens(), rewards);

        vm.deal(address(0x1), ethFee);
        farm.claimDividend{value: ethFee}();
        assertEq(dividendToken.balanceOf(address(0x1)), pendingReflection);

        vm.expectRevert("should pay small gas to compound or harvest");
        farm.claimDividend();

        vm.stopPrank();
    }

    function test_updatePool() public {
        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();
        rewardToken.mint(address(farm), rewards);

        // before start staking
        uint256 lastRewardBlock = farm.lastRewardBlock();
        tryDeposit(address(0x1), 0.1 ether);
        assertLe(lastRewardBlock, block.number);

        vm.deal(address(0x1), 1 ether);
        vm.startPrank(address(0x1));
        // deposit did not be made yet
        uint256 lastRewardBlock2 = farm.lastRewardBlock();
        farm.claimReward{value: ethFee}();
        assertEq(lastRewardBlock2, block.number);
        vm.stopPrank();

        tryDeposit(address(0x1), 1 ether);
        dividendToken.mint(address(farm), 0.01 ether);
        assertEq(farm.availableDividendTokens(), 0.01 ether);
        assertEq(farm.lastRewardBlock(), block.number);

        utils.mineBlocks(100);
        uint256 _rewards = farm.rewardPerBlock() * 100;
        uint256 dShare = _rewards * 1e18 / farm.totalStaked();
        uint256 prevAccTokenPerShare = farm.accTokenPerShare();
        uint256 accDividendPerShare = 0.01 ether * 1e18 / farm.totalStaked();

        tryDeposit(address(0x1), 1 ether);
        assertEq(farm.lastRewardBlock(), block.number);
        assertEq(farm.accTokenPerShare(), prevAccTokenPerShare + dShare);
        assertEq(farm.accDividendPerShare(), accDividendPerShare);
    }

    function test_emergencyWithdrawReflections() public {
        dividendToken.mint(address(farm), 100 ether);

        farm.emergencyWithdrawReflections();
        assertEq(dividendToken.balanceOf(farm.owner()), 100 ether);
        assertEq(dividendToken.balanceOf(address(farm)), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.emergencyWithdrawReflections();
    }

    function test_transferToHarvest() public {
        dividendToken.mint(address(farm), 100 ether);

        farm.transferToHarvest();
        assertEq(dividendToken.balanceOf(farm.owner()), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.transferToHarvest();
    }

    function test_availableRewardTokens() public {
        assertEq(farm.availableRewardTokens(), 0);

        rewardToken.mint(address(farm), 10 ether);
        assertEq(farm.availableRewardTokens(), 10 ether);
    }

    function test_availableDividendTokens() public {
        assertEq(farm.availableDividendTokens(), 0);

        dividendToken.mint(address(farm), 1 ether);
        assertEq(farm.availableDividendTokens(), 1 ether);
    }

    function test_insufficientRewards() public {
        uint256 expectedRewards = farm.rewardPerBlock() * 365 * 28800;
        assertEq(farm.insufficientRewards(), expectedRewards);

        rewardToken.mint(address(farm), farm.insufficientRewards() - 10000);
        assertEq(farm.insufficientRewards(), 10000);

        vm.startPrank(farm.owner());
        rewardToken.mint(farm.owner(), 10000);
        rewardToken.approve(address(farm), 10000);
        farm.depositRewards(10000);
        assertEq(farm.insufficientRewards(), 0);
        vm.stopPrank();
    }

    function test_setSettings() public {
        vm.expectEmit(true, true, false, true);
        emit SetSettings(DEPOSIT_FEE, WITHDRAW_FEE, address(0x1));
        farm.setSettings(DEPOSIT_FEE, WITHDRAW_FEE, address(0x1));
    }

    function testFailed_setSettingsInNotOwner() public {
        vm.prank(address(0x2));
        farm.setSettings(DEPOSIT_FEE, WITHDRAW_FEE, address(0x1));
    }

    function test_swapSetting() public {
        address[] memory path;
        farm.setSwapSetting(address(0x1), path, path, path, path, true);
    }

    function test_setServiceInfo() public {
        vm.startPrank(farm.treasury());
        vm.expectEmit(false, false, false, true);
        emit ServiceInfoUpadted(farm.treasury(), 100);
        farm.setServiceInfo(farm.treasury(), 100);

        vm.expectRevert(abi.encodePacked("Invalid address"));
        farm.setServiceInfo(address(0), 200);
        vm.stopPrank();

        vm.expectRevert(abi.encodePacked("setServiceInfo: FORBIDDEN"));
        farm.setServiceInfo(address(0x1), 200);
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

    function test_updateEmissionRate() public {
        vm.expectEmit(false, false, false, true);
        emit NewRewardPerBlock(1e9);
        farm.updateEmissionRate(1e9);

        assertEq(farm.rewardPerBlock(), 1e9);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.updateEmissionRate(111);
    }

    function test_startReward() public {
        BrewlabsFarmImpl _farm = new BrewlabsFarmImpl();
        _farm.initialize(
            lpToken,
            rewardToken,
            address(dividendToken),
            1e18,
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            true,
            _farm.owner(),
            _farm.owner()
        );

        _farm.startReward();
        assertEq(_farm.startBlock(), block.number + 100);
        assertEq(_farm.bonusEndBlock(), block.number + 365 * 28800 + 100);

        vm.expectRevert(abi.encodePacked("Pool was already started"));
        _farm.startReward();

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("caller is not owner or operator"));
        _farm.startReward();
    }

    function test_depositRewards() public {
        rewardToken.mint(farm.owner(), 100 ether);

        rewardToken.approve(address(farm), 100 ether);

        farm.depositRewards(100 ether);
        assertEq(rewardToken.balanceOf(address(farm)), 100 ether);
        assertEq(farm.availableRewardTokens(), 100 ether);

        vm.expectRevert(abi.encodePacked("invalid amount"));
        farm.depositRewards(0);
    }

    function test_increaseEmissionRate() public {
        uint256 amount = farm.insufficientRewards();
        amount += 100 ether;

        rewardToken.mint(farm.owner(), amount);
        rewardToken.approve(address(farm), amount);

        vm.roll(farm.startBlock());
        vm.expectEmit(true, false, false, true);
        emit NewRewardPerBlock(amount / BLOCKS_PER_DAY / 365);
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

    function test_emergencyRewardWithdraw() public {
        rewardToken.mint(address(farm), 100 ether);

        vm.expectRevert(abi.encodePacked("Pool is running"));
        farm.emergencyRewardWithdraw(10 ether);

        vm.roll(farm.bonusEndBlock() + 1);

        farm.emergencyRewardWithdraw(10 ether);
        assertEq(rewardToken.balanceOf(farm.owner()), 10 ether);

        farm.emergencyRewardWithdraw(0);
        assertEq(rewardToken.balanceOf(address(farm)), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.emergencyRewardWithdraw(111);
    }

    function test_rescueTokens() public {
        vm.expectRevert(abi.encodePacked("cannot recover reward token or reflection token"));
        farm.rescueTokens(address(rewardToken));

        vm.expectRevert(abi.encodePacked("cannot recover reward token or reflection token"));
        farm.rescueTokens(address(dividendToken));

        vm.expectRevert(abi.encodePacked("token is using on pool"));
        farm.rescueTokens(address(lpToken));

        MockErc20 _token = new MockErc20(18);

        _token.mint(address(farm), 1 ether);
        farm.rescueTokens(address(_token));
        assertEq(_token.balanceOf(address(farm)), 0);
        assertEq(_token.balanceOf(address(farm.owner())), 1 ether);

        uint256 ownerBalance = address(farm.owner()).balance;

        vm.deal(address(farm), 0.5 ether);
        farm.rescueTokens(address(0x0));
        assertEq(address(farm).balance, 0);
        assertEq(address(farm.owner()).balance, ownerBalance + 0.5 ether);
    }
}

contract BrewlabsFarmImplWithSameTest is BrewlabsFarmImplBase {
    function setUp() public {
        rewardToken = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsFarmImpl();
        farm.initialize(
            lpToken,
            rewardToken,
            address(rewardToken),
            1e18,
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            true,
            farm.owner(),
            farm.owner()
        );

        farm.startReward();
        utils.mineBlocks(101);
    }

    function test_availableRewardTokens() public {
        rewardToken.mint(address(farm), 1 ether);
        assertEq(farm.availableRewardTokens(), 0 ether);
        assertEq(farm.availableDividendTokens(), 1 ether);

        rewardToken.mint(farm.owner(), 10 ether);

        vm.startPrank(farm.owner());
        rewardToken.approve(address(farm), 10 ether);
        farm.depositRewards(10 ether);
        assertEq(farm.availableRewardTokens(), 10 ether);
        assertEq(farm.availableDividendTokens(), 1 ether);

        vm.stopPrank();
    }
}

contract BrewlabsFarmImplWithETHReflectionTest is BrewlabsFarmImplBase {
    function setUp() public {
        rewardToken = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsFarmImpl();
        farm.initialize(
            lpToken, rewardToken, address(0x0), 1e18, DEPOSIT_FEE, WITHDRAW_FEE, true, farm.owner(), farm.owner()
        );

        farm.startReward();
        utils.mineBlocks(101);
    }

    function tryDeposit(address _user, uint256 _amount) internal {
        lpToken.mint(_user, _amount);
        vm.deal(_user, farm.performanceFee());

        vm.startPrank(_user);
        lpToken.approve(address(farm), _amount);

        uint256 _depositFee = _amount * DEPOSIT_FEE / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, _amount - _depositFee);
        farm.deposit{value: farm.performanceFee()}(_amount);
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
        rewardToken.mint(address(farm), rewards);

        tryDeposit(address(_user), 1 ether);
        vm.deal(address(farm), 0.01 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(address(_user));
        uint256 pendingReflection = farm.pendingReflections(address(_user));
        tryDeposit(address(_user), 1 ether);
        assertEq(rewardToken.balanceOf(address(_user)), pending);
        assertEq(address(_user).balance, pendingReflection);
    }

    function test_withdraw() public {
        address payable _user = utils.getNextUserAddress();

        uint256 rewards = farm.insufficientRewards();
        rewardToken.mint(address(farm), rewards);

        tryDeposit(address(_user), 1 ether);
        vm.deal(address(farm), 0.01 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(address(_user));
        uint256 pendingReflection = farm.pendingReflections(address(_user));

        vm.startPrank(_user);

        uint256 ethFee = farm.performanceFee();
        vm.deal(_user, ethFee);
        farm.withdraw{value: ethFee}(0.1 ether);
        assertEq(rewardToken.balanceOf(address(_user)), pending);
        assertEq(address(_user).balance, pendingReflection);
    }

    function test_claimDividend() public {
        address payable _user = utils.getNextUserAddress();

        uint256 rewards = farm.insufficientRewards();
        uint256 ethFee = farm.performanceFee();

        rewardToken.mint(address(farm), rewards);

        tryDeposit(address(_user), 1 ether);
        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        vm.deal(address(farm), 0.1 ether);
        assertEq(farm.availableDividendTokens(), 0.1 ether);

        vm.roll(farm.startBlock() + 100);
        uint256 pendingReflection = farm.pendingReflections(address(_user));
        vm.deal(address(_user), ethFee);

        vm.startPrank(address(_user));
        farm.claimDividend{value: ethFee}();
        assertEq(address(_user).balance, pendingReflection);
        vm.stopPrank();
    }
}
