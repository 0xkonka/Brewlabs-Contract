// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { MockErc20 } from "../../../contracts/mocks/MockErc20.sol";
import { MetaMerceLocker } from "../../../contracts/others/MetaMerceLocker.sol";

import { Utils } from "../utils/Utils.sol";

contract MetaMerceLockerTest is Test {
  MetaMerceLocker public locker;
  MockErc20 public token;
  Utils internal utils;

  event AddDistribution(address indexed distributor, uint256 allocation, uint256 duration, uint256 unlockBlock);
  event UpdateDistribution(address indexed distributor, uint256 allocation, uint256 duration, uint256 unlockBlock);
  event WithdrawDistribution(address indexed distributor, uint256 amount, uint256 reflection);
  event RemoveDistribution(address indexed distributor);
  event UpdateLockDuration(uint256 Days);

  function setUp() public {
    locker = new MetaMerceLocker();
    token = new MockErc20();
    utils = new Utils();
  }

  function itInitialize() public {
    locker.initialize(token, address(token));

    vm.expectRevert(abi.encodePacked("already initialized"));
    locker.initialize(token, address(token));
  }

  function itDistributors(uint index, address user) public {
    assertEq(locker.distributors(index), user);
  }

  function testAddDistribution(address distributor, uint256 allocation) public {
    itInitialize();

    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    uint256 allocAmt = allocation * 10**token.decimals();

    vm.expectEmit(true, false, false, true);
    emit AddDistribution(distributor, allocAmt, locker.lockDuration(), block.number + locker.lockDuration() * 28800);

    locker.addDistribution(distributor, allocation);
    assertEq(locker.totalDistributed(), allocAmt);
    itDistributors(0, distributor);

    (address user, uint256 amount, uint256 unlockBlock, bool claimed) = locker.distributions(distributor);
    assertEq(user, distributor);
    assertEq(amount, allocAmt);
    assertEq(unlockBlock, block.number + locker.lockDuration() * 28800);
    assertTrue(!claimed);

    vm.expectRevert(abi.encodePacked("already set"));
    locker.addDistribution(distributor, allocation);

    vm.prank(address(0x1));
    vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
    locker.addDistribution(distributor, allocation);
  }

  function testRemoveDistribution(address distributor, uint256 allocation) public {
    itInitialize();
    
    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    vm.expectRevert(abi.encodePacked("Not found"));
    locker.removeDistribution(distributor);

    locker.addDistribution(distributor, allocation);

    vm.expectEmit(true, false, false, false);
    emit RemoveDistribution(distributor);
    locker.removeDistribution(distributor);
    (address user, uint256 amount, uint256 unlockBlock, ) = locker.distributions(distributor);
    assertEq(user, address(0x0));
    assertEq(amount, 0);
    assertEq(unlockBlock, 0);

    vm.expectRevert(abi.encodePacked("Not found"));
    locker.removeDistribution(distributor);

    vm.prank(address(0x1));
    vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
    locker.removeDistribution(distributor);
  }

  function testRemoveDistributionFailWithClaimed(address distributor, uint256 allocation) public {
    itInitialize();
    
    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    locker.addDistribution(distributor, allocation);
    vm.roll(block.number + locker.lockDuration() * 28800 + 1);

    vm.expectRevert(abi.encodePacked("ERC20: transfer amount exceeds balance"));
    locker.withdrawDistribution(distributor);

    uint256 allocAmt = allocation * 10**token.decimals();
    token.mintTo(address(this), allocAmt);
    token.approve(address(locker), allocAmt);
    locker.depositToken(allocAmt);
    locker.withdrawDistribution(distributor);

    vm.expectRevert(abi.encodePacked("Already claimed"));
    locker.removeDistribution(distributor);
  }

  function testUpdateDistribution(address distributor, uint256 allocation) public {
    itInitialize();
    
    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    vm.expectRevert(abi.encodePacked("Not found"));
    locker.updateDistribution(distributor, allocation);

    locker.addDistribution(distributor, allocation);
    
    uint256 allocAmt = (allocation + 1) * 10**token.decimals();

    vm.expectEmit(true, false, false, true);
    emit UpdateDistribution(distributor, allocAmt, locker.lockDuration(), block.number + locker.lockDuration() * 28800);
    locker.updateDistribution(distributor, allocation + 1);
    
    (, uint256 amount,,) = locker.distributions(distributor);
    assertEq(amount, allocAmt);

    vm.roll(block.number + locker.lockDuration() * 28800 + 1);
    vm.expectRevert(abi.encodePacked("cannot update"));
    locker.updateDistribution(distributor, allocation);

    token.mintTo(address(this), allocAmt);
    token.approve(address(locker), allocAmt);
    locker.depositToken(allocAmt);
    locker.withdrawDistribution(distributor);

    vm.expectRevert(abi.encodePacked("already withdrawn"));
    locker.updateDistribution(distributor, allocation);
  }

  function testWithdrawDistribution(address distributor, uint256 allocation) public {
    itInitialize();
    
    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    vm.expectRevert(abi.encodePacked("not claimable"));
    locker.withdrawDistribution(distributor);

    locker.addDistribution(distributor, allocation);

    vm.expectRevert(abi.encodePacked("not claimable"));
    locker.withdrawDistribution(distributor);
    

    vm.roll(block.number + locker.lockDuration() * 28800 + 1);
    (, uint256 amount,,) = locker.distributions(distributor);

    token.mintTo(address(this), amount);
    token.approve(address(locker), amount);
    locker.depositToken(amount);
    vm.expectEmit(true, false, false, true);
    emit WithdrawDistribution(distributor, amount, 0);
    locker.withdrawDistribution(distributor);

    vm.expectRevert(abi.encodePacked("not claimable"));
    locker.withdrawDistribution(distributor);
  }

  function testPendingRelections(uint256[5] memory allocs, uint256[] memory amounts) public {
    itInitialize();
    
    vm.assume(amounts.length < 10 && amounts.length > 0);
    uint256 decimals = token.decimals();

    address payable[] memory users = utils.createUsers(6);
    uint256[5] memory allocations;
    uint256 pending;
    for(uint i = 0; i < 5; i++) {
      vm.assume(allocs[i] < 10**6 && allocs[i] > 0);
      allocations[i] = allocs[i] * 10**decimals;

      locker.addDistribution(users[i], allocs[i]);
      pending = locker.pendingReflection(users[i]);
      assertEq(pending, 0);
    }

    pending = locker.pendingReflection(users[5]);
    assertEq(pending, 0);

    token.mintTo(address(this), locker.totalDistributed());
    token.approve(address(locker), locker.totalDistributed());
    locker.depositToken(locker.totalDistributed());

    uint256 _accReflectionPerShare = 0;
    for(uint i = 0; i < 1; i++) {
      vm.assume(amounts[i] < 10**22 && amounts[i] > 0);

      token.mintTo(address(locker), amounts[i]);

      _accReflectionPerShare += amounts[i] * (1 ether) / locker.totalDistributed();
      pending = locker.pendingReflection(users[1]);
      assertEq(pending, allocations[1] * _accReflectionPerShare / (1 ether));
    }
    
    vm.roll(block.number + locker.lockDuration() * 28800 + 1);
    locker.withdrawDistribution(users[1]);
    
    pending = locker.pendingReflection(users[1]);
    assertEq(pending, 0);

    _accReflectionPerShare += amounts[0] * (1 ether) / locker.totalDistributed();
    token.mintTo(address(locker), amounts[0]);
    pending = locker.pendingReflection(users[2]);
    assertEq(pending, _accReflectionPerShare * allocations[2] / (1 ether));
  }

  function testClaimable() public {
    itInitialize();
    
    address payable user = utils.getNextUserAddress();

    bool status = locker.claimable(user);
    assertTrue(!status);

    locker.addDistribution(user, 1);

    status = locker.claimable(user);
    assertTrue(!status);

    token.mintTo(address(this), 1 ether);
    token.approve(address(locker), 1 ether);
    locker.depositToken(1 ether);

    vm.roll(block.number + locker.lockDuration() * 28800 + 1);

    status = locker.claimable(user);
    assertTrue(status);

    locker.withdrawDistribution(user);
    status = locker.claimable(user);
    assertTrue(!status);
  }
  
  function testAvailableAllocatedTokens(uint256[7] memory amounts) public {
    itInitialize();
    
    uint256 amount = locker.availableAllocatedTokens();
    assertEq(amount, 0);

    token.mintTo(address(locker), 1 ether);
    amount = locker.availableAllocatedTokens();
    assertEq(amount, 0);

    uint256 total = 0;
    for(uint i = 0; i < 7; i++) {
      vm.assume(amounts[i] < 10**22 && amounts[i] > 0);
      token.mintTo(address(this), amounts[i]);
      token.approve(address(locker), amounts[i]);
      locker.depositToken(amounts[i]);

      total += amounts[i];

      amount = locker.availableAllocatedTokens();
      assertEq(amount, total);
    }
  }

  function testAvailableDividendTokens(uint256[7] memory amounts) public {
    itInitialize();
    
    uint256 amount = locker.availableDividendTokens();
    assertEq(amount, 0);

    token.mintTo(address(this), 1 ether);
    token.approve(address(locker), 1 ether);
    locker.depositToken(1 ether);

    amount = locker.availableDividendTokens();
    assertEq(amount, 0);

    uint256 total = 0;
    for(uint i = 0; i < 7; i++) {
      vm.assume(amounts[i] < 10**22 && amounts[i] > 0);
      token.mintTo(address(locker), amounts[i]);

      total += amounts[i];
      amount = locker.availableDividendTokens();
      assertEq(amount, total);
    }
  }

  function testSetLockDuration() public {
    itInitialize();
    
    vm.expectRevert(abi.encodePacked("Invalid duration"));
    locker.setLockDuration(0);

    vm.expectEmit(false, false, false, true);
    emit UpdateLockDuration(20);
    locker.setLockDuration(20);
  }

  function testDepositToken(uint256 amount) public {
    itInitialize();
    
    vm.expectRevert(abi.encodePacked("invalid amount"));
    locker.depositToken(0);

    vm.assume(amount < 10**22 && amount > 0);

    token.mintTo(address(this), amount);
    token.approve(address(locker), amount);
    locker.depositToken(amount);

    assertEq(locker.availableAllocatedTokens(), amount);
  }
}
