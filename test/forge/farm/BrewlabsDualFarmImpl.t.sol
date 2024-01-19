// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {BrewlabsDualFarmImpl, IERC20} from "../../../contracts/farm/BrewlabsDualFarmImpl.sol";
import {Utils} from "../utils/Utils.sol";

contract BrewlabsDualFarmImplBase is Test {
    MockErc20 internal rewardToken;
    MockErc20 internal rewardToken2;
    MockErc20 internal lpToken;
    Utils internal utils;

    BrewlabsDualFarmImpl internal farm;

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
    event NewRewardsPerBlock(uint256[2] rewardsPerBlock);
    event RewardsStop(uint256 blockNumber);
    event EndBlockChanged(uint256 blockNumber);

    event ServiceInfoChanged(address addr, uint256 fee);
    event DurationUpdated(uint256 duration);
    event SetAutoAdjustableForRewardRate(bool status);
    event SetRewardFee(uint256 fee);
    event OperatorTransferred(address oldOperator, address newOperator);
    event SetSettings(uint256 depositFee, uint256 withdrawFee, address feeAddr);

    receive() external payable {}
}

contract BrewlabsDualFarmImplTest is BrewlabsDualFarmImplBase {
    function setUp() public {
        rewardToken = new MockErc20(18);
        rewardToken2 = new MockErc20(18);
        lpToken = new MockErc20(18);
        utils = new Utils();

        farm = new BrewlabsDualFarmImpl();
        farm.initialize(
            lpToken,
            [IERC20(rewardToken), IERC20(rewardToken2)],
            [uint256(1e18), uint256(1e18)],
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            365,
            farm.owner(),
            address(0x0),
            farm.owner()
        );
        rewardToken.mint(address(farm), farm.insufficientRewards(0));
        rewardToken2.mint(address(farm), farm.insufficientRewards(1));

        farm.startReward();
        utils.mineBlocks(101);
    }

    function test_depositInNotStartedPool() public {
        BrewlabsDualFarmImpl _farm = new BrewlabsDualFarmImpl();
        _farm.initialize(
            lpToken,
            [IERC20(rewardToken), IERC20(rewardToken2)],
            [uint256(1e18), uint256(1e18)],
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            365,
            farm.owner(),
            address(0x0),
            farm.owner()
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

        rewardToken.mint(address(_farm), _farm.insufficientRewards(0));
        rewardToken2.mint(address(_farm), _farm.insufficientRewards(1));
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

        uint256 _depositFee = (_amount * DEPOSIT_FEE) / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(_user, _amount - _depositFee);
        farm.deposit{value: farm.performanceFee()}(_amount);
        vm.stopPrank();
    }

    function test_firstDeposit() public {
        uint256 treasuryVal = address(farm.treasury()).balance;
        tryDeposit(address(0x1), 1 ether);

        (uint256 amount, uint256 rewardDebt, uint256 reflectionDebt) = farm
            .userInfo(address(0x1));

        uint256 _depositFee = (1 ether * DEPOSIT_FEE) / 10000;
        assertEq(amount, 1 ether - _depositFee);
        assertEq(lpToken.balanceOf(farm.feeAddress()), _depositFee);
        assertEq(rewardDebt, 0);
        assertEq(reflectionDebt, 0);
        assertEq(
            address(farm.treasury()).balance - treasuryVal,
            farm.performanceFee()
        );

        vm.expectRevert(abi.encodePacked("Amount should be greator than 0"));
        farm.deposit(0);

        lpToken.mint(address(0x1), 1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 1 ether);
        vm.expectRevert(
            abi.encodePacked("should pay small gas to compound or harvest")
        );
        farm.deposit(1 ether);
    }

    function test_notFirstDeposit() public {
        uint256 rewards = farm.availableRewardTokens(0);

        tryDeposit(address(0x1), 1 ether);

        vm.roll(farm.startBlock() + 100);
        uint256[2] memory pendings = farm.pendingRewards(address(0x1));

        tryDeposit(address(0x1), 1 ether);
        assertEq(rewardToken.balanceOf(address(0x1)), pendings[0]);
        assertEq(farm.availableRewardTokens(0), rewards - pendings[1]);
    }

    function test_depositAfterStakingIsFinished() public {
        uint256 rewards = farm.insufficientRewards(0);
        rewardToken.mint(address(farm), rewards);

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
        uint256 rewards = farm.availableRewardTokens(0);
        tryDeposit(address(0x1), 1 ether);
        tryDeposit(address(0x2), 1.2 ether);

        uint256 rewardFee = 100;
        vm.startPrank(farm.owner());
        farm.setRewardFee(rewardFee);
        vm.stopPrank();

        vm.roll(farm.startBlock() + 100);
        uint256[2] memory pendings = farm.pendingRewards(address(0x1));

        lpToken.mint(address(0x1), 0.1 ether);
        vm.deal(address(0x1), farm.performanceFee());

        vm.startPrank(address(0x1));
        lpToken.approve(address(farm), 0.1 ether);
        uint256 bonusEndBlock = farm.bonusEndBlock();
        uint256 remainRewards = rewards;
        uint256 shouldTotalPaid = farm.rewardsPerBlock(0) *
            (block.number - farm.lastRewardBlock());
        if (remainRewards > shouldTotalPaid) {
            remainRewards =
                remainRewards -
                shouldTotalPaid +
                (pendings[0] - (pendings[0] * (10000 - rewardFee)) / 10000);
        }
        uint256 _expectedRewards = remainRewards /
            (bonusEndBlock - block.number);

        uint256 _depositFee = (0.1 ether * DEPOSIT_FEE) / 10000;
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(0x1), 0.1 ether - _depositFee);
        vm.expectEmit(false, false, false, true);
        emit NewRewardsPerBlock([_expectedRewards, _expectedRewards]);
        farm.deposit{value: farm.performanceFee()}(0.1 ether);

        assertEq(
            rewardToken.balanceOf(address(0x1)),
            (pendings[0] * (10000 - rewardFee)) / 10000
        );
        assertEq(
            farm.availableRewardTokens(0),
            rewards - (pendings[0] * (10000 - rewardFee)) / 10000
        );
    }

    function test_fuzzDeposit(uint96[10] memory _amounts) public {
        uint256 rewards = farm.insufficientRewards(0);
        rewardToken.mint(address(farm), rewards);

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

        (uint256 amount, uint256 rewardDebt, ) = farm.userInfo(address(0x1));
        uint256 rewards = 1000 * farm.rewardsPerBlock(0);
        uint256 accTokenPerShare = farm.accTokensPerShare(0) +
            (rewards * 1e18) /
            farm.totalStaked();
        uint256 pending = (amount * accTokenPerShare) / 1e18 - rewardDebt;
        assertEq(farm.pendingRewards(address(0x1))[0], pending);

        utils.mineBlocks(100);
        rewards = 1100 * farm.rewardsPerBlock(0);
        accTokenPerShare =
            farm.accTokensPerShare(0) +
            (rewards * 1e18) /
            farm.totalStaked();
        pending = (amount * accTokenPerShare) / 1e18;
        assertEq(farm.pendingRewards(address(0x1))[0], pending);
    }

    function test_withdraw() public {
        uint256 rewards = farm.availableRewardTokens(0);
        uint256 ethFee = farm.performanceFee();

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        (uint256 amount, , ) = farm.userInfo(address(0x1));
        uint256 _withdrawFee = (amount * WITHDRAW_FEE) / 10000;
        uint256 pending = farm.pendingRewards(address(0x1))[0];

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Amount to withdraw too high"));
        farm.withdraw{value: ethFee}(amount + 10);

        vm.startPrank(address(0x1));
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(0x1), amount);
        farm.withdraw{value: ethFee}(amount);
        assertEq(rewardToken.balanceOf(address(0x1)), pending);
        assertEq(lpToken.balanceOf(address(0x1)), amount - _withdrawFee);
        assertEq(farm.pendingRewards(address(0x1))[0], 0);
        assertEq(farm.availableRewardTokens(0), rewards - pending);
        vm.stopPrank();

        vm.deal(address(0x1), ethFee);

        tryDeposit(address(0x1), 0.1 ether);
        utils.mineBlocks(100);

        vm.startPrank(address(0x1));
        vm.expectRevert("should pay small gas to compound or harvest");
        farm.withdraw(0.001 ether);

        vm.deal(address(0x1), ethFee);
        vm.expectRevert(abi.encodePacked("Amount should be greator than 0"));
        farm.withdraw{value: ethFee}(0);

        (amount, , ) = farm.userInfo(address(0x1));
        farm.withdraw{value: ethFee}(amount);
        vm.stopPrank();

        vm.startPrank(address(0x2));
        vm.deal(address(0x2), ethFee);
        (amount, , ) = farm.userInfo(address(0x2));
        farm.withdraw{value: ethFee}(amount);
        vm.stopPrank();
    }

    function test_claimReward() public {
        uint256 ethFee = farm.performanceFee();
        uint256 rewards = farm.availableRewardTokens(0);

        tryDeposit(address(0x1), 1 ether);

        utils.mineBlocks(2);
        tryDeposit(address(0x2), 2 ether);

        vm.startPrank(address(0x1));
        vm.roll(farm.startBlock() + 100);
        uint256 pending = farm.pendingRewards(address(0x1))[0];
        assertEq(rewardToken.balanceOf(address(0x1)), 0);
        vm.deal(address(0x1), ethFee);
        farm.claimReward{value: ethFee}();
        assertEq(rewardToken.balanceOf(address(0x1)), pending);

        assertEq(farm.pendingRewards(address(0x1))[0], 0);
        assertEq(farm.availableRewardTokens(0), rewards - pending);

        vm.expectRevert("should pay small gas to compound or harvest");
        farm.claimReward();

        vm.stopPrank();
    }

    function test_updatePool() public {
        uint256 rewards = farm.insufficientRewards(0);
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
        assertEq(farm.lastRewardBlock(), block.number);

        utils.mineBlocks(100);
        uint256 _rewards = farm.rewardsPerBlock(0) * 100;
        uint256 dShare = (_rewards * 1e18) / farm.totalStaked();
        uint256 prevAccTokenPerShare = farm.accTokensPerShare(0);

        tryDeposit(address(0x1), 1 ether);
        assertEq(farm.lastRewardBlock(), block.number);
        assertEq(farm.accTokensPerShare(0), prevAccTokenPerShare + dShare);
    }

    function test_availableRewardTokens() public {
        uint256 oldBalance = farm.availableRewardTokens(0);
        rewardToken.mint(address(farm), 10 ether);
        assertEq(farm.availableRewardTokens(0), oldBalance + 10 ether);
    }

    function test_insufficientRewards() public {
        uint256 rewards = farm.availableRewardTokens(0);

        farm.updateEmissionRate(
            [farm.rewardsPerBlock(0) + 0.1 ether, farm.rewardsPerBlock(1)]
        );

        uint256 expectedRewards = farm.rewardsPerBlock(0) * 365 * 28800;
        assertLt(farm.insufficientRewards(0), expectedRewards - rewards);

        rewardToken.mint(address(farm), farm.insufficientRewards(0) - 10000);
        assertEq(farm.insufficientRewards(0), 10000);

        vm.startPrank(farm.owner());
        rewardToken.mint(farm.owner(), 10000);
        rewardToken.approve(address(farm), 10000);
        farm.depositRewards(0, 10000);
        assertEq(farm.insufficientRewards(0), 0);
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

    function test_setServiceInfo() public {
        vm.startPrank(farm.treasury());
        vm.expectEmit(false, false, false, true);
        emit ServiceInfoChanged(farm.treasury(), 100);
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
        emit NewRewardsPerBlock([1e9, farm.rewardsPerBlock(1)]);
        farm.updateEmissionRate([1e9, farm.rewardsPerBlock(1)]);

        assertEq(farm.rewardsPerBlock(0), 1e9);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.updateEmissionRate([uint256(1e9), uint256(1e9)]);
    }

    function test_startReward() public {
        BrewlabsDualFarmImpl _farm = new BrewlabsDualFarmImpl();
        _farm.initialize(
            lpToken,
            [IERC20(rewardToken), IERC20(rewardToken2)],
            [uint256(1e18), uint256(1e18)],
            DEPOSIT_FEE,
            WITHDRAW_FEE,
            365,
            farm.owner(),
            address(0x0),
            farm.owner()
        );

        vm.expectRevert(
            abi.encodePacked("All reward tokens have not been deposited")
        );
        _farm.startReward();

        rewardToken.mint(address(_farm), _farm.insufficientRewards(0));
        rewardToken2.mint(address(_farm), _farm.insufficientRewards(1));
        _farm.startReward();
        assertEq(_farm.startBlock(), block.number + 100);
        assertEq(_farm.bonusEndBlock(), block.number + 365 * 28800 + 100);

        vm.expectRevert(abi.encodePacked("Pool was already started"));
        _farm.startReward();

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Caller is not owner or operator"));
        _farm.startReward();
    }

    function test_depositRewards() public {
        uint256 rewards = farm.availableRewardTokens(0);

        rewardToken.mint(farm.owner(), 100 ether);
        rewardToken.approve(address(farm), 100 ether);

        farm.depositRewards(0, 100 ether);
        assertEq(rewardToken.balanceOf(address(farm)), rewards + 100 ether);
        assertEq(farm.availableRewardTokens(0), rewards + 100 ether);

        vm.expectRevert(abi.encodePacked("invalid amount"));
        farm.depositRewards(0, 0);
    }

    function test_increaseEmissionRate() public {
        uint256 rewards = farm.availableRewardTokens(0);
        uint256 rewards1 = farm.availableRewardTokens(1);
        uint256 amount = 100 ether;

        rewardToken.mint(farm.owner(), amount);
        rewardToken.approve(address(farm), amount);

        vm.roll(farm.startBlock());
        vm.expectEmit(true, false, false, true);
        emit NewRewardsPerBlock(
            [
                (amount + rewards) / BLOCKS_PER_DAY / 365,
                1e18
            ]
        );
        farm.increaseEmissionRate(0, amount);
        assertEq(
            farm.rewardsPerBlock(0),
            (amount + rewards) / BLOCKS_PER_DAY / 365
        );

        vm.expectRevert(abi.encodePacked("invalid amount"));
        farm.increaseEmissionRate(0, 0);

        vm.roll(farm.startBlock() + BLOCKS_PER_DAY * 365 + 1);
        vm.expectRevert(abi.encodePacked("pool was already finished"));
        farm.increaseEmissionRate(0, 100);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.increaseEmissionRate(0, 111);
    }

    function test_emergencyRewardWithdraw() public {
        rewardToken.mint(address(farm), 100 ether);

        vm.expectRevert(abi.encodePacked("Pool is running"));
        farm.emergencyRewardWithdraw(0, 10 ether);

        vm.roll(farm.bonusEndBlock() + 1);

        farm.emergencyRewardWithdraw(0, 10 ether);
        assertEq(rewardToken.balanceOf(farm.owner()), 10 ether);

        farm.emergencyRewardWithdraw(0, 0);
        assertEq(rewardToken.balanceOf(address(farm)), 0);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        farm.emergencyRewardWithdraw(0, 111);
    }

    function test_rescueTokens() public {
        vm.expectRevert(abi.encodePacked("cannot recover reward tokens"));
        farm.rescueTokens(address(rewardToken));

        vm.expectRevert(abi.encodePacked("cannot recover reward tokens"));
        farm.rescueTokens(address(rewardToken2));

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
