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
    }

    function test() public {
        emit log_named_uint("test", 128);
    }

}
