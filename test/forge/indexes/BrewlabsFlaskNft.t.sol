// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BrewlabsFlaskNft, IERC721} from "../../../contracts/indexes/BrewlabsFlaskNft.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {MockErc721Staking} from "../../../contracts/mocks/MockErc721Staking.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsFlaskNftTest is Test {
    using stdStorage for StdStorage;

    BrewlabsFlaskNft internal nft;
    MockErc20 internal brewsToken;
    MockErc20 internal feeToken;
    address internal nftOwner;

    Utils internal utils;

    event BaseURIUpdated(string uri);
    event MintEnabled();
    event ItemUpgraded(uint256[3] tokenIds, uint256 newTokenId);
    event SetFeeToken(address token);
    event SetFeeWallet(address wallet);
    event SetMintPrice(uint256 ethFee, uint256 brewsFee);
    event Whitelisted(address indexed account, uint256 count);

    function setUp() public {
        utils = new Utils();

        nft = new BrewlabsFlaskNft();
        nftOwner = nft.owner();

        brewsToken = new MockErc20(9);
        feeToken = new MockErc20(18);

        vm.startPrank(nftOwner);

        nft.setBrewlabsToken(brewsToken);
        nft.setFeeToken(address(feeToken), true);
        nft.setMintPrice(0.01 ether, 1 ether);
        nft.setStakingAddress(address(0x1234));
        nft.enableMint();

        vm.stopPrank();
    }

    function test_Mint() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();

        uint256 numToMint = 5;
        brewsToken.mint(user, brewsMintFee * numToMint);
        feeToken.mint(user, stableMintFee * numToMint);

        vm.startPrank(user);
        feeToken.approve(address(nft), stableMintFee * numToMint);
        brewsToken.approve(address(nft), brewsMintFee * numToMint);

        nft.mint(numToMint, feeToken);
        assertEq(nft.balanceOf(user), numToMint);

        assertEq(brewsToken.balanceOf(nft.treasury()), (brewsMintFee * numToMint));
        assertEq(feeToken.balanceOf(nft.treasury()), (stableMintFee * numToMint) / 4);
        assertEq(feeToken.balanceOf(nft.brewsWallet()), (stableMintFee * numToMint) / 4);
        assertEq(feeToken.balanceOf(nft.stakingAddr()), (stableMintFee * numToMint) / 2);

        vm.stopPrank();
    }

    function test_freeMintForWhitelistedUser() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        vm.startPrank(nftOwner);
        nft.addToWhitelist(user, 3);
        vm.stopPrank();

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();

        uint256 numToMint = 5;
        brewsToken.mint(user, brewsMintFee * (numToMint - 3));
        feeToken.mint(user, stableMintFee * (numToMint - 3));

        vm.startPrank(user);
        feeToken.approve(address(nft), stableMintFee * (numToMint - 3));
        brewsToken.approve(address(nft), brewsMintFee * (numToMint - 3));

        nft.mint(1, feeToken);
        assertEq(nft.balanceOf(user), 1);
        assertEq(nft.whitelist(user), 2);

        assertEq(brewsToken.balanceOf(nft.treasury()), 0);
        assertEq(feeToken.balanceOf(nft.treasury()), 0);
        assertEq(feeToken.balanceOf(nft.brewsWallet()), 0);
        assertEq(feeToken.balanceOf(nft.stakingAddr()), 0);

        nft.mint(numToMint - 1, feeToken);
        assertEq(nft.whitelist(user), 0);
        assertEq(nft.balanceOf(user), numToMint);

        assertEq(brewsToken.balanceOf(nft.treasury()), (brewsMintFee * (numToMint - 3)));
        assertEq(feeToken.balanceOf(nft.treasury()), (stableMintFee * (numToMint - 3)) / 4);
        assertEq(feeToken.balanceOf(nft.brewsWallet()), (stableMintFee * (numToMint - 3)) / 4);
        assertEq(feeToken.balanceOf(nft.stakingAddr()), (stableMintFee * (numToMint - 3)) / 2);
        vm.stopPrank();
    }

    function test_failMintWithInsufficientFeeToken() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        uint256 brewsMintFee = nft.brewsMintFee();
        brewsToken.mint(user, brewsMintFee);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsMintFee);

        vm.expectRevert("Insufficient fee");
        nft.mint(1, feeToken);

        vm.stopPrank();
    }

    function test_failMintWithNotAllowedFeeToken() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        MockErc20 token = new MockErc20(18);

        vm.startPrank(user);
        vm.expectRevert("Not allowed for mint");
        nft.mint(1, token);

        vm.stopPrank();
    }

    function test_failMintWithZeroAmount() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        vm.expectRevert("Invalid amount");
        nft.mint(0, feeToken);

        vm.stopPrank();
    }

    function test_failMintWithInsufficientAllowance() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();
        feeToken.mint(user, brewsMintFee);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsMintFee - 100);
        feeToken.approve(address(nft), stableMintFee);

        vm.expectRevert("ERC20: insufficient allowance");
        nft.mint(1, feeToken);

        vm.stopPrank();
    }

    function test_failMintWithInsufficientApproval() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        uint256 brewsMintFee = nft.brewsMintFee();
        feeToken.mint(user, brewsMintFee);

        vm.startPrank(user);
        feeToken.approve(address(nft), brewsMintFee - 100);

        vm.expectRevert("ERC20: insufficient allowance");
        nft.mint(1, feeToken);

        vm.stopPrank();
    }

    function test_failMintWithInsufficientToken() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();
        brewsToken.mint(user, brewsMintFee - 100);
        feeToken.mint(user, stableMintFee);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsMintFee);
        feeToken.approve(address(nft), stableMintFee);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        nft.mint(1, feeToken);

        vm.stopPrank();
    }

    function test_failMintWithExceedOneTimeLimit() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        vm.expectRevert("Cannot exceed one-time limit");
        nft.mint(31, feeToken);

        vm.stopPrank();
    }

    function test_failMintInMintNotEnabled() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);

        BrewlabsFlaskNft _nft = new BrewlabsFlaskNft();

        vm.startPrank(user);
        vm.expectRevert("Mint is disabled");
        _nft.mint(1, feeToken);

        vm.stopPrank();
    }

    function test_mintTo() public {}

    // function test_upgradeItem() public {
    //     address user = address(0x12345);
    //     vm.deal(user, 100 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee * 100);

    //     vm.startPrank(user);
    //     feeToken.approve(address(nft), brewsMintFee * 100);

    //     uint256[3] memory tokenIds;
    //     uint256 count = 0;
    //     for (uint256 i = 0; i < 100; i++) {
    //         uint256 tokenId = nft.mint(1, feeToken);
    //         if (nft.rarityOf(tokenId) == 0) {
    //             tokenIds[count] = tokenId;
    //             count++;
    //             if (count == 3) break;
    //         }
    //     }
    //     if (count < 3) return;

    //     uint256 newTokenId = nft.upgradeItem(tokenIds);
    //     assertEq(nft.rarityOf(newTokenId), 1);

    //     vm.stopPrank();
    // }

    // function test_failUpgradeItemWithUnsupportedItems() public {
    //     address user = address(0x12345);
    //     vm.deal(user, 100 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee * 100);

    //     vm.startPrank(user);
    //     feeToken.approve(address(nft), brewsMintFee * 100);

    //     uint256[3] memory tokenIds;
    //     uint256 count = 0;
    //     for (uint256 i = 0; i < 100; i++) {
    //         uint256 tokenId = nft.mint(1, feeToken);
    //         if (nft.rarityOf(tokenId) == 0 && count < 2) {
    //             tokenIds[count] = tokenId;
    //             count++;

    //             if (tokenIds[0] > 2) break;
    //         } else if (nft.rarityOf(tokenId) > 1) {
    //             tokenIds[0] = tokenId;
    //             if (count == 2) break;
    //         }
    //     }

    //     if (count < 2 || tokenIds[0] == 0) return;

    //     vm.expectRevert("Only common or uncommon NFT can be upgraded");
    //     nft.upgradeItem(tokenIds);

    //     vm.stopPrank();
    // }

    // function test_failUpgradeItemWithDifferentRarities() public {
    //     address user = address(0x12345);
    //     vm.deal(user, 100 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee * 100);

    //     vm.startPrank(user);
    //     feeToken.approve(address(nft), brewsMintFee * 100);

    //     uint256[3] memory tokenIds;
    //     tokenIds[0] = nft.mint(1, feeToken);
    //     tokenIds[1] = nft.mint(1, feeToken);

    //     for (uint256 i = 0; i < 100; i++) {
    //         uint256 tokenId = nft.mint(1, feeToken);
    //         if (nft.rarityOf(tokenId) != nft.rarityOf(tokenIds[0])) {
    //             tokenIds[2] = tokenId;
    //             break;
    //         }
    //     }

    //     vm.expectRevert("Rarities should be same");
    //     nft.upgradeItem(tokenIds);

    //     vm.stopPrank();
    // }

    // function test_failUpgradeItemWithSameIds() public {
    //     address user = address(0x12345);
    //     vm.deal(user, 100 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee * 100);

    //     vm.startPrank(user);
    //     feeToken.approve(address(nft), brewsMintFee * 100);

    //     uint256[3] memory tokenIds;
    //     tokenIds[0] = nft.mint(1, feeToken);
    //     tokenIds[1] = tokenIds[0];
    //     tokenIds[2] = tokenIds[0];

    //     vm.expectRevert("ERC721: invalid token ID");
    //     nft.upgradeItem(tokenIds);

    //     vm.stopPrank();
    // }

    // function test_NewMintOwnerRegistered() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 1 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee);

    //     vm.startPrank(user);
    //     feeToken.approve(address(nft), brewsMintFee);
    //     uint256 tokenId = nft.mint(1, feeToken);
    //     vm.stopPrank();

    //     uint256 slotOfNewOwner = stdstore.target(address(nft)).sig(nft.ownerOf.selector).with_key(tokenId).find();
    //     uint160 ownerOfTokenIdOne = uint160(uint256((vm.load(address(nft), bytes32(abi.encode(slotOfNewOwner))))));
    //     assertEq(address(ownerOfTokenIdOne), user);
    // }

    // function test_BalanceIncremented() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 1 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee * 2);

    //     vm.startPrank(user);

    //     feeToken.approve(address(nft), brewsMintFee * 2);

    //     uint256 slotBalance = stdstore.target(address(nft)).sig(nft.balanceOf.selector).with_key(user).find();

    //     nft.mint(1, feeToken);
    //     uint256 balanceFirstMint = uint256(vm.load(address(nft), bytes32(slotBalance)));
    //     assertEq(balanceFirstMint, 1);

    //     utils.mineBlocks(10);

    //     nft.mint(1, feeToken);
    //     uint256 balanceSecondMint = uint256(vm.load(address(nft), bytes32(slotBalance)));
    //     assertEq(balanceSecondMint, 2);
    //     vm.stopPrank();
    // }

    // function test_checkMetadata() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 1 ether);

    //     uint256 stableMintFee = nft.mintFee();
    //     uint256 brewsMintFee = nft.brewsMintFee();
    //     feeToken.mint(user, brewsMintFee);

    //     vm.startPrank(user);
    //     feeToken.approve(address(nft), brewsMintFee);
    //     uint256 tokenId = nft.mint(1, feeToken);
    //     vm.stopPrank();

    //     vm.startPrank(nftOwner);
    //     nft.setTokenBaseUri("https://test.com/metadata");
    //     vm.stopPrank();

    //     emit log_named_string("metadata", nft.tokenURI(tokenId));
    // }

    // function test_setMintPrice() public {
    //     vm.expectEmit(false, false, false, true);
    //     emit SetMintPrice(0.1 ether, 2 ether);
    //     nft.setMintPrice(0.1 ether, 2 ether);
    // }

    // function test_enableMint() public {
    //     vm.expectRevert(abi.encodePacked("Already enabled"));
    //     nft.enableMint();

    //     BrewlabsFlaskNft _nft = new BrewlabsFlaskNft();

    //     vm.expectEmit(false, false, false, true);
    //     emit MintEnabled();
    //     _nft.enableMint();

    //     assertTrue(_nft.mintAllowed());
    // }

    // function test_setFeeToken() public {
    //     vm.expectRevert(abi.encodePacked("Invalid token"));
    //     nft.setFeeToken(IERC20(address(0x0)));

    //     vm.expectEmit(false, false, false, true);
    //     emit SetFeeToken(address(0x1));
    //     nft.setFeeToken(IERC20(address(0x1)));
    // }

    // function test_setFeeWallet() public {
    //     vm.expectRevert(abi.encodePacked("Invalid address"));
    //     nft.setFeeWallet(address(0x0));

    //     vm.expectEmit(false, false, false, true);
    //     emit SetFeeWallet(address(0x1));
    //     nft.setFeeWallet(address(0x1));
    // }

    // function test_setTokenBaseUri() public {
    //     vm.expectEmit(false, false, false, true);
    //     emit BaseURIUpdated("uri");
    //     nft.setTokenBaseUri("uri");
    // }

    // function test_addToWhitelist() public {
    //     vm.expectEmit(true, false, false, true);
    //     emit Whitelisted(address(0x123), 3);
    //     nft.addToWhitelist(address(0x123), 3);

    //     assertEq(nft.whitelist(address(0x123)), 3);
    // }

    // function test_removeFromWhitelist() public {
    //     vm.expectEmit(true, false, false, true);
    //     emit Whitelisted(address(0x123), 0);
    //     nft.removeFromWhitelist(address(0x123));

    //     assertEq(nft.whitelist(address(0x123)), 0);
    // }

    function test_rescueTokensForEther() public {
        vm.deal(address(nft), 0.02 ether);
        nft.rescueTokens(address(0x0));
        assertEq(address(nft).balance, 0);
    }

    function test_rescueTokensForErc20() public {
        MockErc20 token = new MockErc20(18);
        token.mint(address(nft), 1000 ether);
        nft.rescueTokens(address(token));
        assertEq(token.balanceOf(address(nft)), 0);
    }

    function test_rescueTokensAsOwner() public {
        address owner = nft.owner();
        uint256 prevBalance = owner.balance;

        vm.deal(address(nft), 0.02 ether);
        nft.rescueTokens(address(0x0));

        assertEq(owner.balance, prevBalance + 0.02 ether);
    }

    function test_rescueTokensFailsAsNotOwner() public {
        vm.startPrank(address(0x1));

        vm.deal(address(nft), 0.02 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        nft.rescueTokens(address(0x0));

        vm.stopPrank();
    }

    receive() external payable {}
}
