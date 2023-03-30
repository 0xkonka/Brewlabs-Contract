// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {MockTpkNft} from "../../../contracts/mocks/MockTpkNft.sol";
import {PixelKeeperNftStaking} from "../../../contracts/others/PixelKeeperNftStaking.sol";

import {Utils} from "../utils/Utils.sol";

contract PixelKeeperNftStakingTest is Test {
    PixelKeeperNftStaking public nftStaking;
    MockErc20 public token;
    MockTpkNft public nft;

    Utils internal utils;
    uint256[3] internal rewardPerBlock;

    event Deposit(address indexed user, uint256[] tokenIds);
    event Withdraw(address indexed user, uint256[] tokenIds);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256[] tokenIds);

    function setUp() public {
        nftStaking = new PixelKeeperNftStaking();
        token = new MockErc20(18);
        nft = new MockTpkNft();

        utils = new Utils();

        nftStaking.initialize(nft, token);
        nftStaking.startReward();
        for (uint256 i = 0; i < 3; i++) {
            rewardPerBlock[i] = nftStaking.totalRewardsOfRarity(i) / 365 / 28800;
        }

        utils.mineBlocks(101);
        token.mint(address(nftStaking), 10000 ether);
    }

    function test_firstDeposit() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        nft.mint(0, user);
        nft.mint(1, user);
        nft.mint(1, user);
        nft.mint(2, user);

        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = i + 1;
        }
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, _tokenIds);
        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        (uint256 amount, uint256[] memory tokenIds, uint256[3] memory _amounts) = nftStaking.stakedInfo(user);
        assertEq(amount, 4);
        assertEq(tokenIds.length, 4);
        assertEq(_amounts[0], 1);
        assertEq(_amounts[1], 2);
        assertEq(_amounts[2], 1);

        assertEq(nftStaking.pendingReward(user), 0);
        vm.stopPrank();
    }

    function test_notFirstDeposit() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        nft.mint(0, user);
        nft.mint(1, user);
        nft.mint(1, user);
        nft.mint(2, user);

        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = i + 1;
        }
        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);
        (,, uint256[3] memory _amounts) = nftStaking.stakedInfo(user);

        utils.mineBlocks(10);

        uint256 pending;
        for (uint256 i = 0; i < 3; i++) {
            pending += 10 * _amounts[i] * rewardPerBlock[i];
        }

        nft.mint(1, user);
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 5;

        vm.expectEmit(true, false, false, true);
        emit Claim(user, pending);
        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        vm.stopPrank();
    }

    function test_claim() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        nft.mint(0, user);
        nft.mint(1, user);
        nft.mint(1, user);
        nft.mint(2, user);

        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = i + 1;
        }
        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        utils.mineBlocks(10);

        nft.mint(1, user);
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 5;

        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        utils.mineBlocks(74);
        (,, uint256[3] memory _amounts) = nftStaking.stakedInfo(user);
        uint256 pending;
        for (uint256 i = 0; i < 3; i++) {
            pending += 74 * _amounts[i] * rewardPerBlock[i];
        }

        vm.expectEmit(true, false, false, true);
        emit Claim(user, pending);
        nftStaking.claimReward{value: 0.0035 ether}();
        vm.stopPrank();
    }

    function test_withdraw() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        nft.mint(0, user);
        nft.mint(1, user);
        nft.mint(1, user);
        nft.mint(2, user);

        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = i + 1;
        }
        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        utils.mineBlocks(10);

        nft.mint(1, user);
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 5;

        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        utils.mineBlocks(74);
        (,, uint256[3] memory _amounts) = nftStaking.stakedInfo(user);
        uint256 pending;
        for (uint256 i = 0; i < 3; i++) {
            pending += 74 * _amounts[i] * rewardPerBlock[i];
        }

        _tokenIds = new uint256[](3);
        for (uint256 i = 3; i > 0; i--) {
            _tokenIds[3 - i] = i + 2;
        }

        vm.expectEmit(true, false, false, true);
        emit Claim(user, pending);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(user, _tokenIds);
        nftStaking.withdraw{value: 0.0035 ether}(3);

        (,, _amounts) = nftStaking.stakedInfo(user);
        assertEq(_amounts[0], 1);
        assertEq(_amounts[1], 1);
        assertEq(_amounts[2], 0);

        vm.stopPrank();
    }

    function test_emergencyWithdraw() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        nft.mint(0, user);
        nft.mint(1, user);
        nft.mint(1, user);
        nft.mint(2, user);

        nft.setApprovalForAll(address(nftStaking), true);

        uint256[] memory _tokenIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            _tokenIds[i] = i + 1;
        }
        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        utils.mineBlocks(10);

        nft.mint(1, user);
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 5;

        nftStaking.deposit{value: 0.0035 ether}(_tokenIds);

        utils.mineBlocks(74);
        (,, uint256[3] memory _amounts) = nftStaking.stakedInfo(user);
        uint256 pending;
        for (uint256 i = 0; i < 3; i++) {
            pending += 74 * _amounts[i] * rewardPerBlock[i];
        }

        _tokenIds = new uint256[](5);
        for (uint256 i = 5; i > 0; i--) {
            _tokenIds[5 - i] = i;
        }

        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(user, _tokenIds);
        nftStaking.emergencyWithdraw();

        (,, _amounts) = nftStaking.stakedInfo(user);
        assertEq(_amounts[0], 0);
        assertEq(_amounts[1], 0);
        assertEq(_amounts[2], 0);

        vm.stopPrank();
    }
}
