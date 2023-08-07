// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";

import {BrewlabsNftDiscountMgr} from "../../../contracts/indexes/BrewlabsNftDiscountMgr.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {MockErc721} from "../../../contracts/mocks/MockErc721WithRarity.sol";

contract BrewlabsNftDiscountMgrTest is Test {
    BrewlabsNftDiscountMgr internal discountMgr;
    MockErc721 internal nft;

    event SetNftCollection(address nft);
    event SetCheckingLimit(uint256 limit);
    event SetDiscountValues(uint256[] discounts);
    event SetDiscountValue(uint256 rarity, uint256 discount);

    function setUp() public {
        discountMgr = new BrewlabsNftDiscountMgr();
        nft = new MockErc721();
    }

    function test_discountOf() public {
        address user = address(0x11111);
        nft.mint(user, 1);
        assertEq(discountMgr.discountOf(user), 0);

        uint256[] memory discounts = new uint256[](4);
        discounts[0] = 100;
        discounts[1] = 500;
        discounts[2] = 2000;
        discounts[3] = 3000;
        discountMgr.setCollection(address(nft));
        discountMgr.setDiscounts(discounts);

        assertEq(discountMgr.discountOf(user), 100);
        assertEq(discountMgr.discountOf(address(0x1234)), 0);

        nft.mint(user, 4);
        assertEq(discountMgr.discountOf(user), 3000);
    }

    function test_setCollection() public {
        vm.startPrank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        discountMgr.setCollection(address(nft));
        vm.stopPrank();

        vm.expectEmit(false, false, false, true);
        emit SetNftCollection(address(nft));
        discountMgr.setCollection(address(nft));
        assertEq(discountMgr.nftCollection(), address(nft));
    }

    function test_setCheckingLimit() public {
        vm.startPrank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        discountMgr.setCheckingLimit(10);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true);
        emit SetCheckingLimit(10);
        discountMgr.setCheckingLimit(10);
        assertEq(discountMgr.checkLimit(), 10);
    }

    function test_setDiscounts() public {
        uint256[] memory discounts = new uint256[](4);
        discounts[0] = 100;
        discounts[1] = 500;
        discounts[2] = 2000;
        discounts[3] = 3000;

        vm.startPrank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        discountMgr.setDiscounts(discounts);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true);
        emit SetDiscountValues(discounts);
        discountMgr.setDiscounts(discounts);

        for (uint256 i = 0; i < 4; i++) {
            assertEq(discountMgr.discounts(i), discounts[i]);
        }

        discounts = new uint256[](3);
        discounts[0] = 100;
        discounts[1] = 500;
        discounts[2] = 2000;
        discountMgr.setDiscounts(discounts);

        assertEq(discountMgr.discounts(3), 0);
    }

    function test_setDiscount() public {
        vm.startPrank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        discountMgr.setDiscount(2, 1000);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true);
        emit SetDiscountValue(2, 1000);
        discountMgr.setDiscount(2, 1000);
        assertEq(discountMgr.discounts(2), 1000);
    }
}
