// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsFarmImpl, IERC20} from "../../../contracts/farm/BrewlabsFarmImpl.sol";
import {BrewlabsDualFarmImpl} from "../../../contracts/farm/BrewlabsDualFarmImpl.sol";
import {BrewlabsFarmFactory} from "../../../contracts/farm/BrewlabsFarmFactory.sol";
import {IBrewlabsFarm} from "../../../contracts/farm/IBrewlabsFarm.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsFarmFactoryTest is Test {
    address internal BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    uint256 internal FEE_DENOMINATOR = 10000;

    address internal farmOwner = address(0x111);
    address internal deployer = address(0x123);

    BrewlabsFarmFactory internal factory;
    MockErc20 internal lpToken;
    MockErc20 internal rewardToken;
    MockErc20 internal rewardToken1;

    Utils internal utils;

    event FarmCreated(
        address indexed farm,
        uint256 category,
        uint256 version,
        address lpToken,
        address rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend,
        address deployer
    );
    event SetFarmOwner(address newOwner);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(uint256 category, address impl, uint256 version);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    function setUp() public {
        utils = new Utils();

        factory = new BrewlabsFarmFactory();
        BrewlabsFarmImpl impl = new BrewlabsFarmImpl();
        factory.initialize(address(impl), BUSD, 1 ether, farmOwner);

        lpToken = new MockErc20(18);
        rewardToken = new MockErc20(18);
        rewardToken1 = new MockErc20(18);
    }

    function test_initialize() public {
        BrewlabsFarmFactory _factory = new BrewlabsFarmFactory();
        BrewlabsFarmImpl impl = new BrewlabsFarmImpl();

        vm.expectEmit(false, false, false, true);
        emit SetImplementation(0, address(impl), 1);
        _factory.initialize(address(impl), BUSD, 1 ether, farmOwner);

        assertEq(_factory.implementation(0), address(impl));
        assertEq(_factory.version(0), 1);
        assertEq(_factory.farmCount(), 0);
    }

    function test_failInitializeWithZeroImpl() public {
        BrewlabsFarmFactory _factory = new BrewlabsFarmFactory();

        vm.expectRevert("Invalid implementation");
        _factory.initialize(address(0), BUSD, 1 ether, farmOwner);
    }

    function test_setImplementation() public {
        vm.expectRevert("Invalid implementation");
        factory.setImplementation(0, address(0));

        BrewlabsFarmImpl impl = new BrewlabsFarmImpl();
        vm.expectEmit(false, false, false, true);
        emit SetImplementation(0, address(impl), 2);
        factory.setImplementation(0, address(impl));

        assertEq(factory.implementation(0), address(impl));
        assertEq(factory.version(0), 2);
    }

    function test_setFarmOwner() public {
        vm.expectRevert("Invalid address");
        factory.setFarmOwner(address(0));

        vm.expectEmit(false, false, false, true);
        emit SetFarmOwner(address(0x1));
        factory.setFarmOwner(address(0x1));
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

    function test_createBrewlabsFarmInETHfee() public {
        factory.setPayingToken(address(0));

        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Not enough fee");
        factory.createBrewlabsFarm(
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            365,
            false
        );

        vm.expectEmit(false, false, false, true);
        emit FarmCreated(
            address(0),
            0,
            1,
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            false,
            deployer
        );
        address farm = factory.createBrewlabsFarm{value: 1 ether}(
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            365,
            false
        );

        assertEq(IBrewlabsFarm(farm).deployer(), deployer);
        assertEq(IBrewlabsFarm(farm).owner(), farmOwner);

        vm.stopPrank();
    }

    function test_createBrewlabsFarmInNoFee() public {
        factory.setPayingToken(address(0));
        factory.addToWhitelist(deployer);

        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);

        vm.expectEmit(false, false, false, true);
        emit FarmCreated(
            address(0),
            0,
            1,
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            false,
            deployer
        );
        address farm = factory.createBrewlabsFarm(
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            365,
            false
        );

        assertEq(IBrewlabsFarm(farm).deployer(), deployer);
        assertEq(IBrewlabsFarm(farm).owner(), farmOwner);
        vm.stopPrank();
    }

    function test_createBrewlabsDualFarmInNoFee() public {
        factory.setPayingToken(address(0));
        factory.addToWhitelist(deployer);
        BrewlabsDualFarmImpl impl = new BrewlabsDualFarmImpl();
        factory.setImplementation(1, address(impl));
        vm.deal(deployer, 10 ether);
        vm.startPrank(deployer);

        vm.expectEmit(false, false, false, true);
        emit FarmCreated(
            address(0),
            1,
            1,
            address(lpToken),
            address(rewardToken),
            address(rewardToken1),
            0,
            100,
            100,
            false,
            deployer
        );
        address farm = factory.createBrewlabsDualFarm(
            address(lpToken),
            [address(rewardToken), address(rewardToken1)],
            [uint256(0), uint256(0)],
            100,
            100,
            365
        );

        assertEq(IBrewlabsFarm(farm).deployer(), deployer);
        assertEq(IBrewlabsFarm(farm).owner(), farmOwner);
        vm.stopPrank();
    }

    function test_failcreateBrewlabsFarmInNoInitialized() public {
        BrewlabsFarmFactory _factory = new BrewlabsFarmFactory();

        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Not initialized yet");
        _factory.createBrewlabsFarm(
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            365,
            false
        );
        vm.stopPrank();
    }

    function test_failcreateBrewlabsFarmInvalidLP() public {
        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Invalid LP token");
        factory.createBrewlabsFarm(
            address(0),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            100,
            365,
            false
        );
        vm.stopPrank();
    }

    function test_failcreateBrewlabsFarmInInvalidRewardToken() public {
        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Invalid reward token");
        factory.createBrewlabsFarm(
            address(lpToken),
            address(0),
            address(0),
            1 ether,
            100,
            100,
            365,
            false
        );
        vm.stopPrank();
    }

    function test_failcreateBrewlabsFarmInvalidDepositFee() public {
        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Invalid deposit fee");
        factory.createBrewlabsFarm(
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            2001,
            100,
            365,
            false
        );
        vm.stopPrank();
    }

    function test_failcreateBrewlabsFarmInvalidWithdrawFee() public {
        vm.deal(deployer, 10 ether);

        vm.startPrank(deployer);
        vm.expectRevert("Invalid withdraw fee");
        factory.createBrewlabsFarm(
            address(lpToken),
            address(rewardToken),
            address(0),
            1 ether,
            100,
            2001,
            365,
            false
        );
        vm.stopPrank();
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
