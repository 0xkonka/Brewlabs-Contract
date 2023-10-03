// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {VboneMigration} from "../../../contracts/others/VboneMigration.sol";

import {Utils} from "../utils/Utils.sol";

contract VboneMigrationTest is Test {
    VboneMigration public migration;
    MockErc20 public vbone;
    MockErc20 public vboneWarmhole;
    Utils internal utils;

    address alice = vm.addr(0xA11CE);
    address bob = vm.addr(0xB0B);

    event Enabled();
    event Disabled();
    event Migrated(address indexed user, uint256 amountA, uint256 amountB);
    event MigratedToVbone(address indexed user, uint256 amountA, uint256 amountB);
    event MigrationRateChanged(uint256 rate);

    function setUp() public {
        vbone = new MockErc20(6);
        vboneWarmhole = new MockErc20(18);
        migration = new VboneMigration(vbone, vboneWarmhole);

        utils = new Utils();

        vbone.mint(address(migration), 1000 * 10 ** 6);
        vboneWarmhole.mint(address(migration), 1000 ether);
        migration.enableMigration();
    }

    function test_migration() external {
        uint256 amount = 5 * 10 ** 6;
        vbone.mint(alice, amount);

        vm.startPrank(alice);
        vbone.approve(address(migration), amount);

        vm.expectEmit(true, true, true, true);
        emit Migrated(alice, amount, 5 ether);

        migration.migrate(amount);
        vm.stopPrank();

        assertEq(vbone.balanceOf(alice), 0);
        assertEq(vboneWarmhole.balanceOf(alice), 5 ether);
    }
}
