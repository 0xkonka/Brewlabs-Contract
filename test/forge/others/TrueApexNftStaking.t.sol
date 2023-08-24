// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {MockErc721} from "../../../contracts/mocks/MockErc721.sol";
import {TrueApexNftStaking} from "../../../contracts/others/TrueApexNftStaking.sol";

import {Utils} from "../utils/Utils.sol";

contract TrueApexNftStakingTest is Test {
    TrueApexNftStaking public nftStaking;
    MockErc20 public token;
    MockErc721 public nft;

    Utils internal utils;
    uint256[2] internal rewardPerBlock;

    event Deposit(address indexed user, uint256[] tokenIds);
    event Withdraw(address indexed user, uint256[] tokenIds);
    event Claim(address indexed user, address indexed token, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256[] tokenIds);

    function setUp() public {
        token = new MockErc20(18);
        nft = new MockErc721();
        nftStaking = new TrueApexNftStaking();

        utils = new Utils();

        nftStaking.initialize(nft, [address(token), address(0x0)], [uint256(1 ether), 0]);
        nftStaking.startReward();

        vm.warp(block.timestamp + 301);
        token.mint(address(nftStaking), 10000 ether);
    }

    function test_firstDeposit() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = nft.mint(user);
        }
        nft.setApprovalForAll(address(nftStaking), true);

        vm.expectEmit(true, false, false, true);
        emit Deposit(user, _tokenIds);
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        (uint256 amount, uint256[] memory tokenIds) = nftStaking.stakedInfo(user);
        assertEq(amount, 4);
        assertEq(tokenIds.length, 4);

        assertEq(nftStaking.pendingReward(user, 0), 0);
        vm.stopPrank();
    }

    function test_notFirstDeposit() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);
        vm.deal(address(nftStaking), 1 ether);

        vm.startPrank(user);
        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = nft.mint(user);
        }
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        assertEq(nftStaking.rewardsPerSecond(1), uint256(1 ether) / (365 * 86400 - 1));

        vm.warp(block.timestamp + 100);
        uint256 accTokenPerShare0 = 100 * nftStaking.rewardsPerSecond(0) * 10 ** 30 / 4;
        uint256 accTokenPerShare1 = 100 * nftStaking.rewardsPerSecond(1) * 10 ** 30 / 4;
        uint256 pending0 = accTokenPerShare0 * 4 / 10 ** 30;
        uint256 pending1 = accTokenPerShare1 * 4 / 10 ** 30;

        _tokenIds = new uint256[](1);
        _tokenIds[0] = nft.mint(user);

        vm.expectEmit(true, true, false, true);
        emit Claim(user, address(token), pending0);
        vm.expectEmit(true, true, false, true);
        emit Claim(user, address(0), pending1);
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        vm.stopPrank();
    }

    function test_claim() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);
        vm.deal(address(nftStaking), 1 ether);

        vm.startPrank(user);
        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = nft.mint(user);
        }
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        vm.warp(block.timestamp + 100);
        uint256 accTokenPerShare0 = 100 * nftStaking.rewardsPerSecond(0) * 10 ** 30 / 4;
        uint256 accTokenPerShare1 = 100 * nftStaking.rewardsPerSecond(1) * 10 ** 30 / 4;

        nftStaking.withdraw{value: 0.00089 ether}(1);

        vm.warp(block.timestamp + 74);
        uint256 debt0 = 3 * accTokenPerShare0 / 10 ** 30;
        uint256 debt1 = 3 * accTokenPerShare1 / 10 ** 30;
        accTokenPerShare0 += 74 * nftStaking.rewardsPerSecond(0) * 10 ** 30 / 3;
        accTokenPerShare1 += 74 * nftStaking.rewardsPerSecond(1) * 10 ** 30 / 3;
        uint256 pending0 = accTokenPerShare0 * 3 / 10 ** 30 - debt0;
        uint256 pending1 = accTokenPerShare1 * 3 / 10 ** 30 - debt1;

        vm.expectEmit(true, true, false, true);
        emit Claim(user, address(token), pending0);
        nftStaking.claimReward{value: 0.00089 ether}(0);

        vm.expectEmit(true, true, false, true);
        emit Claim(user, address(0), pending1);
        nftStaking.claimReward{value: 0.00089 ether}(1);
        vm.stopPrank();
    }

    function test_withdraw() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);
        vm.deal(address(nftStaking), 1 ether);

        vm.startPrank(user);
        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = nft.mint(user);
        }
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        vm.warp(block.timestamp + 100);
        uint256 accTokenPerShare0 = 100 * nftStaking.rewardsPerSecond(0) * 10 ** 30 / 4;
        uint256 accTokenPerShare1 = 100 * nftStaking.rewardsPerSecond(1) * 10 ** 30 / 4;

        _tokenIds = new uint256[](1);
        _tokenIds[0] = nft.mint(user);
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        vm.warp(block.timestamp + 574);
        uint256 debt0 = 5 * accTokenPerShare0 / 10 ** 30;
        uint256 debt1 = 5 * accTokenPerShare1 / 10 ** 30;
        accTokenPerShare0 += 574 * nftStaking.rewardsPerSecond(0) * 10 ** 30 / 5;
        accTokenPerShare1 += 574 * nftStaking.rewardsPerSecond(1) * 10 ** 30 / 5;
        uint256 pending0 = accTokenPerShare0 * 5 / 10 ** 30 - debt0;
        uint256 pending1 = accTokenPerShare1 * 5 / 10 ** 30 - debt1;

        _tokenIds = new uint256[](3);
        for (uint256 i = 3; i > 0; i--) {
            _tokenIds[3 - i] = i + 2;
        }

        vm.expectEmit(true, true, false, true);
        emit Claim(user, address(token), pending0);
        vm.expectEmit(true, true, false, true);
        emit Claim(user, address(0), pending1);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(user, _tokenIds);
        nftStaking.withdraw{value: 0.00089 ether}(3);

        (uint256 amount,) = nftStaking.stakedInfo(user);
        assertEq(amount, 2);

        vm.stopPrank();
    }

    function test_emergencyWithdraw() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);
        vm.deal(address(nftStaking), 1 ether);

        vm.startPrank(user);
        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = nft.mint(user);
        }
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        vm.warp(block.timestamp + 100);
        _tokenIds = new uint256[](1);
        _tokenIds[0] = nft.mint(user);
        nftStaking.deposit{value: 0.00089 ether}(_tokenIds);

        vm.warp(block.timestamp + 574);
        _tokenIds = new uint256[](5);
        for (uint256 i = 5; i > 0; i--) {
            _tokenIds[5 - i] = i;
        }
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(user, _tokenIds);
        nftStaking.emergencyWithdraw();

        assertEq(nftStaking.rewardsPerSecond(1), address(nftStaking).balance / (365 * 86400 - 101));

        vm.warp(block.timestamp + 10);
        assertEq(nftStaking.pendingReward(user, 0), 0);

        vm.stopPrank();
    }
}
