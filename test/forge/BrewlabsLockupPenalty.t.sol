// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// import "forge-std/console.sol";       // use like hardhat console.log
import {MockErc20} from "../../contracts/mocks/MockErc20.sol";
import {BrewlabsLockupPenalty, IERC20} from "../../contracts/pool/BrewlabsLockupPenalty.sol";
import {Utils} from "./utils/Utils.sol";

contract BrewlabsLockupPenaltyBase is Test {
    MockErc20 internal token;
    MockErc20 internal reflectionToken;
    Utils internal utils;

    BrewlabsLockupPenalty internal pool;

    uint256 internal BLOCKS_PER_DAY = 28800;
    uint256 internal DURATION = 2;
    uint256 internal DEPOSIT_FEE = 10;
    uint256 internal WITHDRAW_FEE = 20;

    event Deposit(address indexed user, uint256 stakeType, uint256 amount);
    event Withdraw(address indexed user, uint256 stakeType, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);
    event SetEmergencyWithdrawStatus(bool status);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event LockupUpdated(uint8 _type, uint256 _duration, uint256 _fee0, uint256 _fee1, uint256 _rate);
    event RewardsStop(uint256 blockNumber);
    event EndBlockUpdated(uint256 blockNumber);
    event UpdatePoolLimit(uint256 poolLimitPerUser, bool hasLimit);

    event ServiceInfoUpadted(address _addr, uint256 _fee);
    event DurationUpdated(uint256 _duration);
    event SetWhiteList(address _whitelist);
    event SetPenaltyStatus(bool status, uint256 fee);

    receive() external payable {}
}

contract BrewlabsLockupPenaltyTest is BrewlabsLockupPenaltyBase {
    function setUp() public {
        token = new MockErc20(18);
        reflectionToken = new MockErc20(18);
        utils = new Utils();

        pool = new BrewlabsLockupPenalty();
        address[] memory path;
        pool.initialize(IERC20(token), IERC20(token), address(reflectionToken), address(0x14444), path, path, address(0x0));
        pool.addLockup(DURATION, DEPOSIT_FEE, WITHDRAW_FEE, 1 ether, 0);
        pool.setPenaltyStatus(true, 1000);

        pool.startReward();
        utils.mineBlocks(101);
    }

    function tryDeposit(address _user, uint8 _pid, uint256 _amount) internal {
        token.mint(_user, _amount);
        vm.deal(_user, pool.performanceFee());

        vm.startPrank(_user);
        token.approve(address(pool), _amount);
        pool.deposit{value: pool.performanceFee()}(_amount, _pid);
        vm.stopPrank();
    }

    function test_withdrawAvailable() public {
        uint256 rewards = pool.insufficientRewards();
        token.mint(address(pool), rewards);

        uint256 ethFee = pool.performanceFee();
        reflectionToken.mint(address(pool), 0.2 ether);

        tryDeposit(address(0x1), 0, 1 ether);
        vm.warp(block.timestamp + DURATION * 1 days + 1);

        vm.startPrank(address(0x1));
        uint256 _withdrawFee = 0.1 ether * WITHDRAW_FEE / 10000;
        uint256 pendingRewards = pool.pendingReward(address(0x1), 0);
        
        vm.deal(address(0x1), ethFee);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(address(0x1), 0, 0.1 ether);
        pool.withdraw{value: ethFee}(0.1 ether, 0);
        assertEq(token.balanceOf(address(0x1)), 0.1 ether + pendingRewards - _withdrawFee);
        vm.stopPrank();
    }

    function test_withdrawMixed() public {
        uint256 rewards = pool.insufficientRewards();
        token.mint(address(pool), rewards);

        uint256 ethFee = pool.performanceFee();
        reflectionToken.mint(address(pool), 0.2 ether);

        tryDeposit(address(0x1), 0, 1 ether);
        vm.warp(block.timestamp + DURATION * 1 days + 1);
        tryDeposit(address(0x1), 0, 1 ether);
        vm.warp(block.timestamp + DURATION * 1 days / 2 + 1);

        vm.startPrank(address(0x1));
        uint256 _withdrawFee = 1.2 ether * WITHDRAW_FEE / 10000;
        uint256 pendingRewards = pool.pendingReward(address(0x1), 0);

        uint256 available = 1 ether - 1 ether * DEPOSIT_FEE / 10000;
        uint256 penaltyFee = (1.2 ether - available) * 1000 / 10000;
        
        vm.deal(address(0x1), ethFee);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(address(0x1), 0, 1.2 ether);
        pool.withdraw{value: ethFee}(1.2 ether, 0);
        assertEq(token.balanceOf(address(0x1)), 1.2 ether + pendingRewards - _withdrawFee - penaltyFee);
        vm.stopPrank();
    }

}
