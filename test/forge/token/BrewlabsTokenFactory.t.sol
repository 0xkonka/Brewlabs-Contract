// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BrewlabsStandardToken, Ownable} from "../../../contracts/token/BrewlabsStandardToken.sol";
import {BrewlabsTokenFactory} from "../../../contracts/token/BrewlabsTokenFactory.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsTokenFactoryTest is Test {
    address internal treasury = address(0x111111);
    address internal deployer = address(0x123);

    BrewlabsTokenFactory internal factory;
    MockErc20 internal payingToken;
    Utils internal utils;

    event StandardTokenCreated(
        address indexed token,
        uint256 category,
        uint256 version,
        string name,
        string symbol,
        uint8 decimals,
        uint256 totalSupply,
        address deployer
    );
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(uint256 category, address impl, uint256 version);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    function setUp() public {
        utils = new Utils();

        payingToken = new MockErc20(18);

        factory = new BrewlabsTokenFactory();
        BrewlabsStandardToken impl = new BrewlabsStandardToken();
        factory.initialize(address(impl), address(payingToken), 1 ether, treasury);
    }

    function test_initialize() public {
        BrewlabsTokenFactory _factory = new BrewlabsTokenFactory();
        BrewlabsStandardToken impl = new BrewlabsStandardToken();

        vm.expectEmit(false, false, false, true);
        emit SetImplementation(0, address(impl), 1);
        _factory.initialize(address(impl), address(payingToken), 1 ether, treasury);

        assertEq(_factory.implementation(0), address(impl));
        assertEq(_factory.version(0), 1);
        assertEq(_factory.tokenCount(), 0);
        assertEq(_factory.treasury(), treasury);
    }

    function test_failInitializeWithZeroImpl() public {
        BrewlabsTokenFactory _factory = new BrewlabsTokenFactory();

        vm.expectRevert("Invalid implementation");
        _factory.initialize(address(0), address(payingToken), 1 ether, treasury);
    }

    function test_createBrewlabsStandardTokenInETHfee() public {
        factory.setPayingToken(address(0));

        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Not enough fee");
        factory.createBrewlabsStandardToken("Test token1", "TEST", 18, 1_000_000 ether);

        uint256 treasuryBalance = address(treasury).balance;

        vm.expectEmit(false, false, false, true);
        emit StandardTokenCreated(address(0), 0, 1, "Test token1", "TEST", 18, 1_000_000 ether, deployer);
        address token = factory.createBrewlabsStandardToken{value: 1 ether}("Test token1", "TEST", 18, 1_000_000 ether);

        assertEq(Ownable(token).owner(), deployer);
        assertEq(IERC20(token).totalSupply(), 1_000_000 ether);
        assertEq(IERC20(token).balanceOf(deployer), 1_000_000 ether);
        assertEq(address(treasury).balance, treasuryBalance + 1 ether);

        assertEq(factory.tokenCount(), 1);

        vm.stopPrank();
    }

    function test_createBrewlabsStandardTokenInTokenfee() public {
        vm.deal(deployer, 1 ether);

        vm.startPrank(deployer);
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createBrewlabsStandardToken("Test token1", "TEST", 18, 1_000_000 ether);

        payingToken.approve(address(factory), 1 ether);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        factory.createBrewlabsStandardToken("Test token1", "TEST", 18, 1_000_000 ether);
        vm.stopPrank();

        payingToken.mint(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectEmit(false, false, false, true);
        emit StandardTokenCreated(address(0), 0, 1, "Test token1", "TEST", 18, 1_000_000 ether, deployer);
        address token = factory.createBrewlabsStandardToken("Test token1", "TEST", 18, 1_000_000 ether);

        assertEq(Ownable(token).owner(), deployer);
        assertEq(IERC20(token).totalSupply(), 1_000_000 ether);
        assertEq(IERC20(token).balanceOf(deployer), 1_000_000 ether);
        assertEq(payingToken.balanceOf(treasury), 1 ether);

        assertEq(factory.tokenCount(), 1);

        vm.stopPrank();
    }

    function test_createBrewlabsStandardTokenInNoFee() public {
        factory.setPayingToken(address(0));
        factory.addToWhitelist(deployer);

        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);

        vm.expectEmit(false, false, false, true);
        emit StandardTokenCreated(address(0), 0, 1, "Test token1", "TEST", 18, 1_000_000 ether, deployer);
        address token = factory.createBrewlabsStandardToken("Test token1", "TEST", 18, 1_000_000 ether);

        assertEq(Ownable(token).owner(), deployer);
        assertEq(IERC20(token).totalSupply(), 1_000_000 ether);
        assertEq(IERC20(token).balanceOf(deployer), 1_000_000 ether);
        assertEq(factory.tokenCount(), 1);

        vm.stopPrank();
    }

    function test_failcreateBrewlabsStandardTokenInNoInitialized() public {
        BrewlabsTokenFactory _factory = new BrewlabsTokenFactory();

        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Not initialized yet");
        _factory.createBrewlabsStandardToken("Test token1", "TEST", 18, 1_000_000 ether);
        vm.stopPrank();
    }

    function test_setImplementation() public {
        vm.expectRevert("Invalid implementation");
        factory.setImplementation(0, address(0));

        BrewlabsStandardToken impl = new BrewlabsStandardToken();
        vm.expectEmit(false, false, false, true);
        emit SetImplementation(0, address(impl), 2);
        factory.setImplementation(0, address(impl));

        assertEq(factory.implementation(0), address(impl));
        assertEq(factory.version(0), 2);
    }

    function test_setServiceFee() public {
        vm.expectEmit(false, false, false, true);
        emit SetPayingInfo(factory.payingToken(), 1 ether);
        factory.setServiceFee(1 ether);
    }

    function test_setPayingToken() public {
        vm.expectEmit(false, false, false, true);
        emit SetPayingInfo(address(0x1), factory.serviceFee());
        factory.setPayingToken(address(0x1));
    }

    function test_addToWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(address(0x1), true);
        factory.addToWhitelist(address(0x1));

        assertTrue(factory.whitelist(address(0x1)));
    }

    function test_removeFromWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(address(0x1), false);
        factory.removeFromWhitelist(address(0x1));

        assertFalse(factory.whitelist(address(0x1)));
    }

    function test_setTreasury() public {
        vm.expectRevert("Invalid address");
        factory.setTreasury(address(0));

        vm.expectEmit(true, false, false, true);
        emit TreasuryChanged(address(0x1));
        factory.setTreasury(address(0x1));
    }

    function test_rescueTokensForEther() public {
        vm.deal(address(factory), 0.02 ether);
        factory.rescueTokens(address(0x0));
        assertEq(address(factory).balance, 0);
    }

    function test_rescueTokensForErc20() public {
        MockErc20 token = new MockErc20(18);
        token.mint(address(factory), 1000 ether);
        factory.rescueTokens(address(token));
        assertEq(token.balanceOf(address(factory)), 0);
    }

    function test_rescueTokensAsOwner() public {
        address owner = factory.owner();
        uint256 prevBalance = owner.balance;

        vm.deal(address(factory), 0.02 ether);
        factory.rescueTokens(address(0x0));

        assertEq(owner.balance, prevBalance + 0.02 ether);
    }

    function test_rescueTokensFailsAsNotOwner() public {
        vm.startPrank(address(0x1));

        vm.deal(address(factory), 0.02 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.rescueTokens(address(0x0));

        vm.stopPrank();
    }

    receive() external payable {}
}
