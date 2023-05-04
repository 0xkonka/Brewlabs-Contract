// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsFlaskNft, IERC721} from "../../../contracts/indexes/BrewlabsFlaskNft.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsFlaskNftTest is Test {
    BrewlabsFlaskNft internal nft;

    Utils internal utils;

    function setUp() public {
        utils = new Utils();

        nft = new ThePixelKeeper();
        nftOwner = nft.owner();

        vm.startPrank(nftOwner);

        feeToken = new MockErc20();
        nft.setFeeToken(address(feeToken));
        nft.setMintPrice(0.1 ether, 1 ether);

        nft.enableMint();

        vm.stopPrank();
    }

    function test_Mint() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        uint256 ethMintFee = nft.ethMintFee();
        uint256 brewsMintFee = nft.brewsMintFee();
        feeToken.mint(user, brewsMintFee);

        vm.startPrank(user);
        feeToken.approve(address(nft), brewsMintFee);

        uint256 tokenId = nft.mint{value: ethMintFee}();

        assertEq(nft.balanceOf(user), 1);
        assertEq(nft.ownerOf(tokenId), user);

        vm.stopPrank();
    }

    // function test_FreeMint(uint256 _numToMint) public {
    //     vm.assume(_numToMint <= 9 && _numToMint > 0);
    //     address _user = address(0x12345);

    //     nft.addToWhitelist(_user);

    //     vm.deal(_user, 0.1 ether);

    //     vm.startPrank(_user);
    //     nft.mint{value: 0.0035 ether}(1, _numToMint);
    //     assertEq(nft.balanceOf(_user), _numToMint);
    //     assertTrue(nft.mintAllowed());
    //     vm.stopPrank();
    // }

    // function testFail_ZeroMintAmount() public {
    //     nft.mint{value: 0.0035 ether}(1, 0);
    // }

    // function testFail_ExceedOneTimeLimit() public {
    //     nft.mint{value: 0.0035 ether}(1, 20);
    // }

    // function testFail_SuperRareLimitReached() public {
    //     address _user = address(0x12345);

    //     uint256 mintPrice = nft.prices(0);
    //     uint256 amount = mintPrice * 25;

    //     vm.deal(_user, 0.1 ether);
    //     feeToken.mint(_user, amount);

    //     vm.startPrank(_user);
    //     feeToken.approve(address(nft), amount);

    //     nft.mint{value: 0.0035 ether}(0, 10);
    //     nft.mint{value: 0.0035 ether}(0, 10);

    //     nft.mint{value: 0.0035 ether}(0, 6);

    //     vm.stopPrank();
    // }

    // function testFail_RareLimitReached() public {
    //     address _user = address(0x12345);

    //     uint256 mintPrice = nft.prices(1);
    //     uint256 amount = mintPrice * 50;

    //     vm.deal(_user, 0.1 ether);
    //     feeToken.mint(_user, amount);

    //     vm.startPrank(_user);
    //     feeToken.approve(address(nft), amount);

    //     nft.mint{value: 0.0035 ether}(1, 10);
    //     nft.mint{value: 0.0035 ether}(1, 10);
    //     nft.mint{value: 0.0035 ether}(1, 10);
    //     nft.mint{value: 0.0035 ether}(1, 10);
    //     nft.mint{value: 0.0035 ether}(1, 10);
    //     nft.mint{value: 0.0035 ether}(1, 1);

    //     vm.stopPrank();
    // }

    // function testFail_CommonLimitReached() public {
    //     address _user = address(0x12345);

    //     ThePixelKeeper _nft = new ThePixelKeeper();
    //     _nft.setFeeToken(address(feeToken));

    //     uint256[] memory tokenIds = new uint256[](2);
    //     tokenIds[0] = 1;
    //     tokenIds[1] = 2;
    //     _nft.setTokenIdsForRarity(0, tokenIds);

    //     tokenIds = new uint256[](497);
    //     for (uint256 i = 0; i < 497; i++) {
    //         tokenIds[i] = i + 3;
    //     }
    //     _nft.setTokenIdsForRarity(1, tokenIds);
    //     _nft.setStakingWallet(address(0x123));
    //     _nft.enableMint();

    //     uint256 mintPrice = _nft.prices(1);
    //     uint256 amount = mintPrice * 3;

    //     vm.deal(_user, 0.1 ether);
    //     feeToken.mint(_user, amount);

    //     vm.startPrank(_user);
    //     feeToken.approve(address(_nft), amount);

    //     vm.expectRevert(abi.encodePacked("No tokens to mint for this rarity"));
    //     _nft.mint{value: 0.0035 ether}(2, 2);

    //     vm.expectEmit(true, false, false, true);
    //     emit Mint(_user, 500);
    //     _nft.mint{value: 0.0035 ether}(2, 1);

    //     _nft.mint{value: 0.0035 ether}(2, 1);
    //     vm.stopPrank();
    // }

    // function testFail_MaxSupplyReached() public {
    //     uint256 slot = stdstore.target(address(nft)).sig("totalSupply()").find();
    //     bytes32 loc = bytes32(slot);
    //     bytes32 mockedCurrentTokenId = bytes32(abi.encode(499));
    //     vm.store(address(nft), loc, mockedCurrentTokenId);

    //     uint256 mintPrice = nft.prices(0);
    //     uint256 amount = 2 * mintPrice;

    //     vm.deal(address(0x1234), 0.1 ether);
    //     feeToken.mint(address(0x1234), amount);

    //     vm.startPrank(address(0x1234));
    //     feeToken.approve(address(nft), amount);
    //     nft.mint{value: 0.0035 ether}(0, 2);
    //     vm.stopPrank();
    // }

    // function test_NewMintOwnerRegistered() public {
    //     vm.deal(address(0x1234), 1 ether);

    //     uint256 mintPrice = nft.prices(0);
    //     uint256 amount = mintPrice;
    //     feeToken.mint(address(0x1234), amount);

    //     vm.startPrank(address(0x1234));
    //     feeToken.approve(address(nft), amount);
    //     vm.expectEmit(true, false, false, true);
    //     emit Mint(address(0x1234), 1);
    //     nft.mint{value: 0.0035 ether}(2, 1);
    //     vm.stopPrank();

    //     uint256 slotOfNewOwner = stdstore.target(address(nft)).sig(nft.ownerOf.selector).with_key(1).find();
    //     uint160 ownerOfTokenIdOne = uint160(uint256((vm.load(address(nft), bytes32(abi.encode(slotOfNewOwner))))));
    //     assertEq(address(ownerOfTokenIdOne), address(0x1234));
    // }

    // function test_BalanceIncremented() public {
    //     vm.deal(address(0x1234), 1 ether);

    //     uint256 mintPrice = nft.prices(2);
    //     uint256 amount = mintPrice;
    //     feeToken.mint(address(0x1234), amount * 2);

    //     vm.startPrank(address(0x1234));
    //     feeToken.approve(address(nft), amount * 2);

    //     nft.mint{value: 0.0035 ether}(2, 1);

    //     uint256 slotBalance = stdstore.target(address(nft)).sig(nft.balanceOf.selector).with_key(address(0x1234)).find();

    //     uint256 balanceFirstMint = uint256(vm.load(address(nft), bytes32(slotBalance)));
    //     assertEq(balanceFirstMint, 1);

    //     nft.mint{value: 0.0035 ether}(2, 1);
    //     uint256 balanceSecondMint = uint256(vm.load(address(nft), bytes32(slotBalance)));
    //     assertEq(balanceSecondMint, 2);
    //     vm.stopPrank();
    // }

    // function test_checkMetadata() public {
    //     vm.deal(address(0x1234), 1 ether);

    //     uint256 mintPrice = nft.prices(2);
    //     uint256 amount = mintPrice;
    //     feeToken.mint(address(0x1234), amount);

    //     nft.setTokenBaseUri("https://test.com/metadata");

    //     vm.startPrank(address(0x1234));
    //     feeToken.approve(address(nft), amount);
    //     nft.mint{value: 0.0035 ether}(2, 1);
    //     vm.stopPrank();

    //     emit log_named_string("metadata", nft.tokenURI(1));
    // }

    // function test_setMintPrices(uint256[3] memory _prices) public {
    //     vm.assume(_prices[0] < 100 ether && _prices[1] < 100 ether && _prices[0] < 100 ether);

    //     vm.expectEmit(false, false, false, true);
    //     emit SetMintPrices(_prices);
    //     nft.setMintPrices(_prices);
    // }

    // function test_enableMint() public {
    //     vm.expectRevert(abi.encodePacked("Already enabled"));
    //     nft.enableMint();

    //     ThePixelKeeper _nft = new ThePixelKeeper();

    //     vm.expectRevert(abi.encodePacked("Not set staking address"));
    //     _nft.enableMint();

    //     _nft.setStakingWallet(address(0x123));
    //     vm.expectRevert(abi.encodePacked("TokenId list not configured"));
    //     _nft.enableMint();

    //     uint256[] memory tokenIds = new uint256[](2);
    //     tokenIds[0] = 1;
    //     tokenIds[1] = 1;
    //     _nft.setTokenIdsForRarity(0, tokenIds);
    //     _nft.setTokenIdsForRarity(1, tokenIds);

    //     vm.expectEmit(false, false, false, true);
    //     emit MintEnabled();
    //     _nft.enableMint();

    //     assertTrue(_nft.mintAllowed());
    // }

    // function test_setOneTimeMintLimit() public {
    //     vm.expectRevert(abi.encodePacked("Cannot exceed 50"));
    //     nft.setOneTimeMintLimit(160);

    //     vm.expectEmit(false, false, false, true);
    //     emit SetOneTimeMintLimit(50);
    //     nft.setOneTimeMintLimit(50);
    // }

    // function test_setAdminWallet() public {
    //     vm.expectRevert(abi.encodePacked("Invalid address"));
    //     nft.setAdminWallet(address(0x0));

    //     vm.expectEmit(false, false, false, true);
    //     emit SetFeeWallet(address(0x1));
    //     nft.setAdminWallet(address(0x1));
    // }

    // function test_setStakingWallet() public {
    //     vm.expectRevert(abi.encodePacked("Invalid address"));
    //     nft.setStakingWallet(address(0x0));

    //     vm.expectEmit(false, false, false, true);
    //     emit SetStakingWallet(address(0x1));
    //     nft.setStakingWallet(address(0x1));
    // }

    // function test_setTokenBaseUri() public {
    //     vm.expectEmit(false, false, false, true);
    //     emit BaseURIUpdated("uri");
    //     nft.setTokenBaseUri("uri");
    // }

    // function test_rescueTokensForEther() public {
    //     vm.deal(address(nft), 0.02 ether);
    //     nft.rescueTokens(address(0x0), 0.02 ether);
    //     assertEq(address(nft).balance, 0);
    // }

    // function test_rescueTokensForErc20() public {
    //     MockErc20 token = new MockErc20();
    //     token.mint(address(nft), 1000 ether);
    //     nft.rescueTokens(address(token), 1000 ether);
    //     assertEq(token.balanceOf(address(nft)), 0);
    // }

    // function testFail_rescueTokens() public {
    //     vm.deal(address(nft), 0.02 ether);
    //     nft.rescueTokens(address(0x0), 0.03 ether);
    // }

    // function test_rescueTokensAsOwner() public {
    //     address owner = nft.owner();
    //     uint256 prevBalance = owner.balance;

    //     vm.deal(address(nft), 0.02 ether);
    //     nft.rescueTokens(address(0x0), 0.02 ether);

    //     assertEq(owner.balance, prevBalance + 0.02 ether);
    // }

    // function test_rescueTokensFailsAsNotOwner() public {
    //     vm.startPrank(address(0x1));

    //     vm.deal(address(nft), 0.02 ether);
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     nft.rescueTokens(address(0x0), 0.02 ether);

    //     vm.stopPrank();
    // }

    receive() external payable {}
}
