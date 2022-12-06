// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {ProjectXLocker} from "../../../contracts/others/ProjectXLocker.sol";

import {Utils} from "../utils/Utils.sol";

contract ProjectXLockerTest is Test {
    ProjectXLocker public locker;
    MockErc20 public token;
    MockErc20 public reflectionToken;
    Utils internal utils;

    event AddDistribution(address indexed distributor, uint256 allocation, uint256 duration);
    event UpdateDistribution(address indexed distributor, uint256 allocation, uint256 duration);
    event RemoveDistribution(address indexed distributor);
    event Claim(address indexed distributor, uint256 amount);
    event Harvest(address indexed distributor, uint256 amount);

    function setUp() public {
        locker = new ProjectXLocker();
        token = new MockErc20();
        reflectionToken = new MockErc20();

        utils = new Utils();
    }

    function itInitialize() public {
        locker.initialize(token, address(reflectionToken));
        locker.setStatus(true);
    }

    function itDistributors(uint256 index, address user) public {
        assertEq(locker.distributors(index), user);
    }

    function testInitialize() public {
        vm.startPrank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        locker.initialize(token, address(reflectionToken));
        vm.stopPrank();

        itInitialize();

        vm.expectRevert(abi.encodePacked("Already initialized"));
        locker.initialize(token, address(reflectionToken));
    }

    function testAddDistribution(address distributor, uint256 allocation, uint256 duration) public {
        itInitialize();

        vm.assume(distributor != address(0x0) && allocation != 0);
        vm.assume(allocation < 10 ** 6);
        vm.assume(duration <= 365);

        vm.startPrank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        locker.addDistribution(address(0x2), 1, 1);
        vm.stopPrank();

        uint256 allocAmt = allocation * 10 ** token.decimals();
        vm.expectEmit(true, false, false, true);
        emit AddDistribution(distributor, allocAmt, duration);

        locker.addDistribution(distributor, allocation, duration);
        assertEq(locker.insufficientTokens(), allocAmt);
        itDistributors(0, distributor);

        (address user, uint256 amount, uint256 lockDuration, uint256 unlockBlock,, bool claimed) =
            locker.distributions(distributor);
        assertEq(user, distributor);
        assertEq(duration, lockDuration);
        assertEq(amount, allocAmt);
        assertEq(unlockBlock, block.number + duration * 28800);
        assertTrue(!claimed);

        vm.expectRevert(abi.encodePacked("Already set"));
        locker.addDistribution(distributor, allocation, duration);
    }

    function testRemoveDistribution(address distributor) public {
        itInitialize();

        vm.assume(distributor != address(0x0));

        vm.expectRevert(abi.encodePacked("Not found"));
        locker.removeDistribution(distributor);

        locker.addDistribution(distributor, 10, 1);

        vm.expectEmit(true, false, false, false);
        emit RemoveDistribution(distributor);
        locker.removeDistribution(distributor);
        (address user, uint256 amount, uint256 lockDuration, uint256 unlockBlock, uint256 reflectionDebt,) =
            locker.distributions(distributor);
        assertEq(user, address(0x0));
        assertEq(amount, 0);
        assertEq(lockDuration, 0);
        assertEq(unlockBlock, 0);
        assertEq(reflectionDebt, 0);

        vm.expectRevert(abi.encodePacked("Not found"));
        locker.removeDistribution(distributor);

        vm.prank(address(0x1));
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        locker.removeDistribution(distributor);
    }

    function testRemoveDistributionFailWithClaimed() public {
        itInitialize();

        address distributor = address(0x1);
        uint256 allocation = 10;
        uint256 duration = 1;
        locker.addDistribution(distributor, allocation, duration);
        vm.roll(block.number + duration * 28800 + 1);

        uint256 allocAmt = allocation * 10 ** token.decimals();
        token.mintTo(address(locker), allocAmt);

        vm.startPrank(distributor);
        locker.claim();
        vm.stopPrank();

        vm.expectRevert(abi.encodePacked("Already claimed"));
        locker.removeDistribution(distributor);
    }

    function testUpdateDistribution(address distributor) public {
        itInitialize();

        vm.assume(distributor != address(0x0));
        uint256 duration = 1;
        uint256 allocation = 10;

        vm.expectRevert(abi.encodePacked("Not found"));
        locker.updateDistribution(distributor, allocation, 1);

        locker.addDistribution(distributor, allocation, 1);
        uint256 allocAmt = (allocation + 1) * 10 ** token.decimals();

        vm.expectEmit(true, false, false, true);
        emit UpdateDistribution(distributor, allocAmt, duration);
        locker.updateDistribution(distributor, allocation + 1, 1);

        (, uint256 amount,,,,) = locker.distributions(distributor);
        assertEq(amount, allocAmt);
        assertEq(locker.insufficientTokens(), allocAmt);

        vm.roll(block.number + duration * 28800 + 1);
        vm.expectRevert(abi.encodePacked("Cannot update"));
        locker.updateDistribution(distributor, allocation + 1, 1);
    }

    function testClaim(address distributor, uint256 allocation, uint256 duration) public {
        itInitialize();

        vm.assume(distributor != address(0x0) && allocation != 0);
        vm.assume(allocation < 10 ** 6);
        vm.assume(duration <= 365 && duration > 0);

        vm.expectRevert(abi.encodePacked("Not found"));
        locker.claim();

        uint256 allocAmt = allocation * 10 ** token.decimals();
        locker.addDistribution(distributor, allocation, duration);

        vm.startPrank(distributor);

        vm.expectRevert(abi.encodePacked("Not unlocked yet"));
        locker.claim();

        vm.roll(block.number + duration * 28800 + 1);
        vm.expectRevert(abi.encodePacked("ERC20: transfer amount exceeds balance"));
        locker.claim();

        token.mintTo(address(locker), allocAmt);
        vm.expectEmit(true, false, false, true);
        emit Claim(distributor, allocAmt);
        locker.claim();

        vm.expectRevert(abi.encodePacked("Already claimed"));
        locker.claim();

        vm.stopPrank();
    }

    function testFailClaimWithInsufficient(address distributor, uint256 allocation, uint256 duration) public {
        itInitialize();

        vm.assume(distributor != address(0x0) && allocation != 0);
        vm.assume(allocation < 10 ** 6);
        vm.assume(duration <= 365);

        vm.expectRevert(abi.encodePacked("Not found"));
        locker.claim();

        uint256 allocAmt = allocation * 10 ** token.decimals();
        locker.addDistribution(distributor, allocation, duration);

        vm.startPrank(distributor);
        token.mintTo(address(locker), allocAmt - 1e9);

        vm.roll(block.number + duration * 28800 + 1);
        locker.claim();

        vm.stopPrank();
    }

    function testHarvest(uint256 amount) public {
        itInitialize();

        vm.assume(amount < 10 ** 22 && amount > 1e10);
        uint256 decimals = token.decimals();
        uint256 duration = 1;

        address payable[] memory users = utils.createUsers(5);
        uint256[5] memory allocations;
        for (uint256 i = 0; i < 5; i++) {
            allocations[i] = (i + 1) * 10 ** decimals;

            locker.addDistribution(users[i], i + 1, duration);
        }

        token.mintTo(address(locker), locker.insufficientTokens());
        reflectionToken.mintTo(address(locker), amount);

        vm.startPrank(users[1]);

        uint256 pending = locker.pendingReflection(users[1]);
        vm.expectEmit(true, false, false, true);
        emit Harvest(users[1], pending);
        locker.harvest();

        assertEq(reflectionToken.balanceOf(users[1]), pending);

        vm.stopPrank();
    }

    function testPendingRelections(uint256[3] memory amounts) public {
        itInitialize();

        uint256 decimals = token.decimals();
        uint256 duration = 1;

        address payable[] memory users = utils.createUsers(5);
        uint256[5] memory allocations;
        uint256 pending;
        for (uint256 i = 0; i < 5; i++) {
            allocations[i] = 100 * (i + 1) * 10 ** decimals;

            locker.addDistribution(users[i], 100 * (i + 1), duration);
            pending = locker.pendingReflection(users[i]);
            assertEq(pending, 0);
        }

        token.mintTo(address(locker), locker.insufficientTokens());

        vm.startPrank(users[1]);

        uint256 accReflectionPerShare = 0;
        uint256 allocatedReflections = 0;
        for (uint256 i = 0; i < 3; i++) {
            vm.assume(amounts[i] < 1e22);
            reflectionToken.mintTo(address(locker), amounts[i]);

            uint256 reflectionAmount = reflectionToken.balanceOf(address(locker));
            if (reflectionAmount > allocatedReflections) {
                reflectionAmount -= allocatedReflections;
            } else {
                reflectionAmount = 0;
            }

            uint256 _accReflectionPerShare =
                accReflectionPerShare + reflectionAmount * (1 ether) / locker.totalAllocated();
            pending = locker.pendingReflection(users[1]);
            (,,,, uint256 reflectionDebt,) = locker.distributions(users[1]);
            assertEq(pending, allocations[1] * _accReflectionPerShare / (1 ether) - reflectionDebt);

            if (i == 0) {
                locker.harvest();

                allocatedReflections += reflectionAmount - pending;
                accReflectionPerShare += reflectionAmount * (1 ether) / locker.totalAllocated();
            }
        }

        // vm.roll(block.number + duration * 28800 + 1);
        // locker.claim();

        // pending = locker.pendingReflection(users[1]);
        // assertEq(pending, 0);

        vm.stopPrank();
    }
}
