// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { MockErc20 } from "../../../contracts/mocks/MockErc20.sol";
import { MetaMerceLocker } from "../../../contracts/others/MetaMerceLocker.sol";

import { Utils } from "../utils/Utils.sol";

contract MetaMerceLockerTest is Test {
  MetaMerceLocker public locker;
  MockErc20 public token;

  event AddDistribution(address indexed distributor, uint256 allocation, uint256 duration, uint256 unlockBlock);
  event UpdateDistribution(address indexed distributor, uint256 allocation, uint256 duration, uint256 unlockBlock);
  event WithdrawDistribution(address indexed distributor, uint256 amount, uint256 reflection);
  event RemoveDistribution(address indexed distributor);
  event UpdateLockDuration(uint256 Days);

  function setUp() public {
    locker = new MetaMerceLocker();
    token = new MockErc20();

    locker.initialize(token, address(token));
  }

  function testAddDistribution(address distributor, uint256 allocation) public {
    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    uint256 allocAmt = allocation * 10**token.decimals();

    vm.expectEmit(true, false, false, true);
    emit AddDistribution(distributor, allocAmt, locker.lockDuration(), block.number + locker.lockDuration() * 28800);

    locker.addDistribution(distributor, allocation);
    assertEq(locker.totalDistributed(), allocAmt);

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
    vm.assume(distributor != address(0x0) && allocation != 0);
    vm.assume(allocation < 10**6);

    vm.expectRevert(abi.encodePacked("Not found"));
    locker.updateDistribution(distributor, allocation);

    locker.addDistribution(distributor, allocation);
    locker.updateDistribution(distributor, allocation + 1);
    
    uint256 allocAmt = (allocation + 1) * 10**token.decimals();
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


  
}
