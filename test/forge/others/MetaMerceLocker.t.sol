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

  function setUp() public {
    locker = new MetaMerceLocker();
    token = new MockErc20();

    locker.initialize(token, address(token));
  }

  function testAddDistribution(address distributor, uint256 allocation) public {
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
}
