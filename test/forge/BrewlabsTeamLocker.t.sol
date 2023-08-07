// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsTeamLocker, IERC20} from "../../contracts/BrewlabsTeamLocker.sol";
import {IUniV2Factory} from "../../contracts/libs/IUniFactory.sol";
import {IUniRouter02} from "../../contracts/libs/IUniRouter02.sol";
import {MockErc20} from "../../contracts/mocks/MockErc20.sol";
import {Utils} from "./utils/Utils.sol";

interface IUniPair {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function getReserves1()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 feePercent, uint32 _blockTimestampLast);

    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

contract BrewlabsTeamLockerTest is Test {
    BrewlabsTeamLocker internal locker;
    Utils internal utils;

    event SetMember(address member, uint256 rate);
    event RemoveMember(address member);
    event Distributed(address member, address token, uint256 amount);

    function setUp() public {
        utils = new Utils();
        locker = new BrewlabsTeamLocker();
    }

    function test_addMember() public {
        vm.expectEmit(true, true, true, true);
        emit SetMember(address(0x1), 30);
        locker.addMember(address(0x1), 30);

        (uint256 numerator, uint256 denominator) = locker.rateOfMember(address(0x1));
        assertEq(locker.numMembers(), 1);
        assertEq(numerator, 30);
        assertEq(denominator, 30);

        for (uint160 i = 0; i < 3; i++) {
            locker.addMember(address(i + 2), 30);
        }

        (numerator, denominator) = locker.rateOfMember(address(0x3));
        assertEq(locker.numMembers(), 4);
        assertEq(numerator, 30);
        assertEq(denominator, 120);
    }

    function test_addMemberFailedForInvalidAddressAndDuplicatedMember() public {
        locker.addMember(address(0x1), 30);

        vm.expectRevert("already set");
        locker.addMember(address(0x1), 20);

        vm.expectRevert("Invalid address");
        locker.addMember(address(0x0), 20);
    }

    function tryAddMembers() internal {
        locker.addMember(address(0x12345), 30);
        locker.addMember(address(0x12346), 30);
        locker.addMember(address(0x12347), 20);
        locker.addMember(address(0x12348), 20);
    }

    function test_removeMember() public {
        tryAddMembers();

        vm.expectRevert("Not found");
        locker.removeMember(address(0x1));

        vm.expectEmit(true, true, true, true);
        emit RemoveMember(address(0x12346));
        locker.removeMember(address(0x12346));

        assertEq(locker.numMembers(), 3);

        (uint256 numerator, uint256 denominator) = locker.rateOfMember(address(0x12345));
        assertEq(numerator, 30);
        assertEq(denominator, 70);

        (numerator, denominator) = locker.rateOfMember(address(0x12346));
        assertEq(numerator, 0);
        assertEq(denominator, 70);

        assertEq(locker.members(1), address(0x12348));

        vm.expectRevert("Not found");
        locker.removeMember(address(0x12346));

        locker.removeMember(address(0x12345));
        locker.removeMember(address(0x12347));
        locker.removeMember(address(0x12348));
        assertEq(locker.rateDenominator(), 0);
    }

    function test_updateMember() public {
        tryAddMembers();

        vm.expectRevert("Not found");
        locker.updateMember(address(0x1), 10);

        vm.expectEmit(true, true, true, true);
        emit SetMember(address(0x12347), 50);
        locker.updateMember(address(0x12347), 50);

        assertEq(locker.numMembers(), 4);

        (uint256 numerator, uint256 denominator) = locker.rateOfMember(address(0x12347));
        assertEq(numerator, 50);
        assertEq(denominator, 130);

        locker.updateMember(address(0x12347), 10);
        (numerator, denominator) = locker.rateOfMember(address(0x12347));
        assertEq(numerator, 10);
        assertEq(denominator, 90);
    }

    function test_distributeSingleToken() public {
        tryAddMembers();

        MockErc20 token = new MockErc20(18);
        token.mint(address(locker), 30 ether);

        address[] memory tokens;
        vm.expectRevert("wrong config");
        locker.distribute(tokens);

        tokens = new address[](1);
        tokens[0] = address(token);
        locker.distribute(tokens);

        uint256 remained = 30 ether;
        for (uint160 i = 0; i < 4; i++) {
            address member = address(0x12345 + i);
            (uint256 numerator, uint256 denominator) = locker.rateOfMember(member);

            uint256 amount = 30 ether * numerator / denominator;
            assertEq(token.balanceOf(member), amount);
            remained -= amount;
        }

        assertEq(token.balanceOf(address(locker)), remained);
    }

    function test_distributeETH() public {
        tryAddMembers();

        vm.deal(address(locker), 0.3 ether);

        address[] memory tokens;
        tokens = new address[](1);
        tokens[0] = address(0x0);
        locker.distribute(tokens);

        uint256 remained = 0.3 ether;
        for (uint160 i = 0; i < 4; i++) {
            address member = address(0x12345 + i);
            (uint256 numerator, uint256 denominator) = locker.rateOfMember(member);

            uint256 amount = 0.3 ether * numerator / denominator;
            assertEq(address(member).balance, amount);
            remained -= amount;
        }

        assertEq(address(locker).balance, remained);
    }

    function test_distributeMultipleTokens() public {
        tryAddMembers();

        vm.deal(address(locker), 0.3 ether);

        MockErc20 _token;
        address[] memory tokens = new address[](10);
        uint256[] memory amounts = new uint256[](10);
        amounts[5] = 0.3 ether;
        for (uint256 i = 0; i < 10; i++) {
            if (i == 5) continue;

            if (i % 2 == 0) {
                _token = new MockErc20(9);
                amounts[i] = 13 gwei * (i + 3);
            } else {
                _token = new MockErc20(18);
                amounts[i] = 1.3 ether * (i + 7);
            }
            _token.mint(address(locker), amounts[i]);

            tokens[i] = address(_token);
        }

        locker.distribute(tokens);

        for (uint256 k = 0; k < 10; k++) {
            address token = tokens[k];
            uint256 balance = amounts[k];

            uint256 remained = balance;
            for (uint160 i = 0; i < 4; i++) {
                address member = address(0x12345 + i);
                (uint256 numerator, uint256 denominator) = locker.rateOfMember(member);

                uint256 amount = balance * numerator / denominator;
                if (token == address(0x0)) {
                    assertEq(address(member).balance, amount);
                } else {
                    assertEq(IERC20(token).balanceOf(address(member)), amount);
                }
                remained -= amount;
            }

            if (token == address(0x0)) {
                assertEq(address(locker).balance, remained);
            } else {
                assertEq(IERC20(token).balanceOf(address(locker)), remained);
            }
        }
    }

    function test_removeLiquidity() public {
        vm.createSelectFork("https://bsc-dataseed.binance.org/");
        
        BrewlabsTeamLocker _locker = new BrewlabsTeamLocker();

        MockErc20 token0 = new MockErc20(18);
        MockErc20 token1 = new MockErc20(18);
        (token0, token1) = address(token0) < address(token1) ? (token0, token1) : (token1, token0);

        address swapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

        _locker.setSwapRouter(swapRouter);

        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 5 ether);
        token0.approve(swapRouter, 10 ether);
        token1.approve(swapRouter, 5 ether);
        IUniRouter02(swapRouter).addLiquidity(address(token0), address(token1), 10 ether, 5 ether, 0, 0, address(_locker), block.timestamp + 200);

        address pair = IUniV2Factory(IUniRouter02(swapRouter).factory()).getPair(address(token0), address(token1));
        uint256 liquidity = MockErc20(pair).balanceOf(address(_locker));
        emit log_named_uint("liquidity", liquidity);
        assertGt(liquidity, 0);

        address[] memory pairs = new address[](1);
        pairs[0] = pair;
        _locker.removeLiquidity(pairs, block.timestamp + 200);
        
        emit log_named_uint("token0", token0.balanceOf(address(_locker)));
        emit log_named_uint("token1", token1.balanceOf(address(_locker)));
    }

    function test_rescueTokensForEther() public {
        uint256 beforeBal = address(locker.owner()).balance;

        vm.deal(address(locker), 0.02 ether);
        locker.rescueTokens(address(0x0), 0);
        assertEq(address(locker).balance, 0);

        uint256 afterBal = address(locker.owner()).balance;
        assertEq(afterBal - beforeBal, 0.02 ether);
    }

    function test_rescueTokensForErc20() public {
        MockErc20 token = new MockErc20(18);
        token.mint(address(locker), 1000 ether);
        locker.rescueTokens(address(token), 0);
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(locker.owner()), 1000 ether);
    }

    function test_rescueTokensForSome() public {
        MockErc20 token = new MockErc20(18);
        token.mint(address(locker), 1000 ether);

        vm.expectRevert("Insufficient balance");
        locker.rescueTokens(address(token), 1700 ether);

        locker.rescueTokens(address(token), 700 ether);
        assertEq(token.balanceOf(address(locker)), 300 ether);
        assertEq(token.balanceOf(locker.owner()), 700 ether);
    }

    function test_rescueTokensAsOwner() public {
        address owner = locker.owner();
        uint256 prevBalance = owner.balance;

        vm.deal(address(locker), 0.02 ether);
        locker.rescueTokens(address(0x0), 0);

        assertEq(owner.balance, prevBalance + 0.02 ether);
    }

    function test_rescueTokensFailsAsNotOwner() public {
        vm.startPrank(address(0x1));

        vm.deal(address(locker), 0.02 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        locker.rescueTokens(address(0x0), 0);

        vm.stopPrank();
    }

    receive() external payable {}
}
