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
        vbone = new MockErc20(18);
        vboneWarmhole = new MockErc20(6);
        migration = new VboneMigration(vbone, vboneWarmhole);

        utils = new Utils();

        vbone.mint(address(migration), 1000 * 10 ether);
        vboneWarmhole.mint(address(migration), 1000 * 10 ** 6);
        migration.enableMigration();
    }

    function test_migration() external {
        uint256 amount = 5 ether;
        vbone.mint(alice, amount);

        vm.startPrank(alice);
        vbone.approve(address(migration), amount);

        vm.expectEmit(true, true, true, true);
        emit Migrated(alice, amount, 5 * 10 ** 6);

        migration.migrate(amount);
        vm.stopPrank();

        assertEq(vbone.balanceOf(alice), 0);
        assertEq(vboneWarmhole.balanceOf(alice), 5 * 10 ** 6);
    }

    function testFail_migrationWithZeroAmount() external {
        vm.startPrank(alice);
        migration.migrate(0);
    }

    function testFail_migrationWhenNotEnabled() external {
        VboneMigration _migration = new VboneMigration(vbone, vboneWarmhole);

        vbone.mint(address(_migration), 1000 ether);
        vboneWarmhole.mint(address(_migration), 1000 * 10 ** 6);

        uint256 amount = 5 ether;
        vbone.mint(alice, amount);

        vm.startPrank(alice);
        vbone.approve(address(_migration), amount);

        _migration.migrate(amount);
        vm.stopPrank();
    }

    function test_migrateToVbone() external {
        uint256 amount = 11 * 10 ** 6;
        vboneWarmhole.mint(bob, amount);

        vm.startPrank(bob);
        vboneWarmhole.approve(address(migration), amount);

        vm.expectEmit(true, true, true, true);
        emit MigratedToVbone(bob, amount, 11 ether);

        migration.migrateToVbone(amount);
        vm.stopPrank();

        assertEq(vbone.balanceOf(bob), 11 ether);
        assertEq(vboneWarmhole.balanceOf(bob), 0);
    }

    function testFail_migrationToVboneWithZeroAmount() external {
        vm.startPrank(alice);
        migration.migrateToVbone(0);
    }
}
