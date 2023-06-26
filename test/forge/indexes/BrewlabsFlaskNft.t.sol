// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BrewlabsFlaskNft, IERC721} from "../../../contracts/indexes/BrewlabsFlaskNft.sol";
import {BrewlabsMirrorNft, IBrewlabsFlaskNft} from "../../../contracts/indexes/BrewlabsMirrorNft.sol";
import {BrewlabsNftStaking, IBrewlabsMirrorNft} from "../../../contracts/BrewlabsNftStaking.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {MockErc721Staking} from "../../../contracts/mocks/MockErc721Staking.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsFlaskNftTest is Test {
    using stdStorage for StdStorage;

    BrewlabsFlaskNft internal nft;
    BrewlabsMirrorNft internal mirrorNft;

    MockErc20 internal brewsToken;
    MockErc20 internal feeToken;
    address internal nftOwner;

    BrewlabsNftStaking internal nftStaking;
    MockErc20 internal earnToken;

    Utils internal utils;

    event BaseURIUpdated(string uri);
    event MintEnabled();

    event ItemUpgraded(uint256[3] tokenIds, uint256 newTokenId);

    event SetBrewlabsToken(address token);
    event SetFeeToken(address token, bool enabled);
    event SetMintPrice(uint256 tokenFee, uint256 brewsFee);
    event SetUpgradePrice(uint256 tokenFee, uint256 brewsFee);
    event SetMaxSupply(uint256 supply);
    event SetOneTimeLimit(uint256 limit);
    event SetMirrorNft(address nftAddr);
    event SetBrewlabsWallet(address addr);
    event SetStakingAddress(address addr);
    event ServiceInfoChanged(address addr, uint256 fee);
    event Whitelisted(address indexed account, uint256 count);

    function setUp() public {
        utils = new Utils();

        nft = new BrewlabsFlaskNft();
        mirrorNft = new BrewlabsMirrorNft(IBrewlabsFlaskNft(address(nft)));
        nft.setMirrorNft(address(mirrorNft));

        brewsToken = new MockErc20(9);
        feeToken = new MockErc20(18);

        // configure nft staking
        nftStaking = new BrewlabsNftStaking();
        earnToken = new MockErc20(18);
        nftStaking.initialize(nft, IBrewlabsMirrorNft(address(mirrorNft)), earnToken, 1 gwei);

        earnToken.mint(address(nftStaking), nftStaking.insufficientRewards());
        nftStaking.startReward();
        nftStaking.setAdmin(address(nft));
        mirrorNft.setAdmin(address(nftStaking));
        utils.mineBlocks(200);

        nftOwner = nft.owner();
        vm.startPrank(nftOwner);

        nft.setBrewlabsToken(brewsToken);
        nft.setFeeToken(address(feeToken), true);
        nft.setMintPrice(0.01 ether, 1 ether);
        nft.setStakingAddress(address(0x1234));
        nft.enableMint();

        nft.setNftStakingContract(address(nftStaking));

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
        assertGt(nft.rarityOf(1), 0);

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

    function test_mintTo() public {
        vm.expectRevert("Invalid rarity");
        nft.mintTo(address(0x11111), 7, 1);

        nft.mintTo(address(0x11111), 4, 1);
        assertEq(nft.ownerOf(1), address(0x11111));
        assertEq(nft.rarityOf(1), 4);

        vm.startPrank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        nft.mintTo(address(0x11111), 4, 1);
        vm.stopPrank();
    }

    function test_transfer() public {
        nft.mintTo(address(0x1111), 2, 1);
        vm.startPrank(address(0x1111));
        nft.safeTransferFrom(address(0x1111), address(0x12345), 1);
    }

    function test_failedMODItemTransfer() public {
        nft.mintTo(address(0x1111), 6, 1);

        vm.startPrank(address(0x1111));
        vm.expectRevert("Cannot transfer Mod item");
        nft.safeTransferFrom(address(0x1111), address(0x12345), 1);
    }

    function test_upgradeItem() public {
        address user = address(0x12345);
        vm.deal(user, 100 ether);

        nft.mintTo(user, 1, 3);
        nft.mintTo(user, 2, 3);

        uint256 upgradeFee = nft.upgradeFee();
        uint256 brewsUpgradeFee = nft.brewsUpgradeFee();
        brewsToken.mint(user, brewsUpgradeFee * 2);
        feeToken.mint(user, upgradeFee * 2);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsUpgradeFee * 2);
        feeToken.approve(address(nft), upgradeFee * 2);

        // upgrade common items
        uint256[3] memory tokenIds;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        uint256 newTokenId = nft.upgradeNFT(tokenIds, feeToken);
        assertEq(nft.rarityOf(newTokenId), nft.rarityOf(tokenIds[0]) + 1);
        assertEq(brewsToken.balanceOf(nft.brewsWallet()), brewsUpgradeFee);
        assertEq(feeToken.balanceOf(nft.stakingAddr()), upgradeFee);

        // upgrade uncommon items
        tokenIds[0] = 4;
        tokenIds[1] = 5;
        tokenIds[2] = 6;

        newTokenId = nft.upgradeNFT(tokenIds, feeToken);
        assertEq(nft.rarityOf(newTokenId), nft.rarityOf(tokenIds[0]) + 1);
        vm.stopPrank();
    }

    function test_failUpgradeItemWithUnsupportedItems() public {
        address user = address(0x12345);
        vm.deal(user, 100 ether);

        nft.mintTo(user, 3, 3);

        vm.startPrank(user);

        uint256[3] memory tokenIds;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        vm.expectRevert("Only common or uncommon NFT can be upgraded");
        nft.upgradeNFT(tokenIds, feeToken);

        vm.stopPrank();
    }

    function test_failUpgradeItemWithDifferentRarities() public {
        address user = address(0x12345);
        vm.deal(user, 100 ether);

        nft.mintTo(user, 1, 2);
        nft.mintTo(user, 2, 2);

        vm.startPrank(user);

        uint256[3] memory tokenIds;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        vm.expectRevert("Rarities should be same");
        nft.upgradeNFT(tokenIds, feeToken);

        vm.stopPrank();
    }

    function test_failUpgradeItemWithSameIds() public {
        address user = address(0x12345);
        vm.deal(user, 100 ether);

        nft.mintTo(user, 1, 3);
        nft.mintTo(user, 2, 3);

        uint256 upgradeFee = nft.upgradeFee();
        uint256 brewsUpgradeFee = nft.brewsUpgradeFee();
        brewsToken.mint(user, brewsUpgradeFee);
        feeToken.mint(user, upgradeFee);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsUpgradeFee);
        feeToken.approve(address(nft), upgradeFee);

        // upgrade common items
        uint256[3] memory tokenIds;
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 2;

        vm.expectRevert("ERC721: invalid token ID");
        nft.upgradeNFT(tokenIds, feeToken);

        vm.stopPrank();
    }

    function test_removeModerator() public {
        address user = address(0x12345);
        vm.deal(user, 0.5 ether);

        nft.mintTo(user, 6, 1);

        nft.removeModerator(1);
        assertEq(nft.balanceOf(user), 0);
        assertEq(nft.rarityOf(1), 0);
    }

    function test_removeModeratorAlreadyStaked() public {
        address user = address(0x12345);
        vm.deal(user, 0.5 ether);

        nft.mintTo(user, 6, 1);

        vm.startPrank(user);
        nft.setApprovalForAll(address(nftStaking), true);

        // stake flask NFT
        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = 1;
        nftStaking.deposit{value: nftStaking.performanceFee()}(_tokenIds);
        // check mirror nft
        assertEq(mirrorNft.ownerOf(_tokenIds[0]), user);
        vm.stopPrank();

        utils.mineBlocks(100);
        uint256 pendingReward = nftStaking.pendingReward(user);

        // remove moderator
        nft.removeModerator(_tokenIds[0]);
        assertEq(nft.balanceOf(user), 0);
        assertEq(mirrorNft.balanceOf(user), 0);
        assertEq(nft.rarityOf(_tokenIds[0]), 0);

        assertEq(earnToken.balanceOf(user), pendingReward);
        (uint256 amount,) = nftStaking.userInfo(user);
        assertEq(amount, 0);
    }

    function test_NewMintOwnerRegistered() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();
        brewsToken.mint(user, brewsMintFee);
        feeToken.mint(user, stableMintFee);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsMintFee);
        feeToken.approve(address(nft), stableMintFee);

        nft.mint(1, feeToken);
        vm.stopPrank();

        uint256 slotOfNewOwner = stdstore.target(address(nft)).sig(nft.ownerOf.selector).with_key(1).find();
        uint160 ownerOfTokenIdOne = uint160(uint256((vm.load(address(nft), bytes32(abi.encode(slotOfNewOwner))))));
        assertEq(address(ownerOfTokenIdOne), user);
    }

    function test_BalanceIncremented() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();
        brewsToken.mint(user, brewsMintFee * 2);
        feeToken.mint(user, stableMintFee * 2);

        vm.startPrank(user);

        brewsToken.approve(address(nft), brewsMintFee * 2);
        feeToken.approve(address(nft), stableMintFee * 2);

        uint256 slotBalance = stdstore.target(address(nft)).sig(nft.balanceOf.selector).with_key(user).find();

        nft.mint(1, feeToken);
        uint256 balanceFirstMint = uint256(vm.load(address(nft), bytes32(slotBalance)));
        assertEq(balanceFirstMint, 1);

        utils.mineBlocks(10);

        nft.mint(1, feeToken);
        uint256 balanceSecondMint = uint256(vm.load(address(nft), bytes32(slotBalance)));
        assertEq(balanceSecondMint, 2);
        vm.stopPrank();
    }

    function test_checkMetadata() public {
        address user = address(0x1234);
        vm.deal(user, 1 ether);

        uint256 stableMintFee = nft.mintFee();
        uint256 brewsMintFee = nft.brewsMintFee();
        brewsToken.mint(user, brewsMintFee);
        feeToken.mint(user, stableMintFee);

        vm.startPrank(user);
        brewsToken.approve(address(nft), brewsMintFee);
        feeToken.approve(address(nft), stableMintFee);

        nft.mint(1, feeToken);
        vm.stopPrank();

        vm.startPrank(nftOwner);
        nft.setTokenBaseUri("https://test.com/metadata");
        vm.stopPrank();

        emit log_named_string("metadata", nft.tokenURI(1));
    }

    function test_setMintPrice() public {
        vm.expectEmit(false, false, false, true);
        emit SetMintPrice(0.1 ether, 2 ether);
        nft.setMintPrice(0.1 ether, 2 ether);
    }

    function test_setUpgradePrice() public {
        vm.expectEmit(false, false, false, true);
        emit SetUpgradePrice(0.1 ether, 2 ether);
        nft.setUpgradePrice(0.1 ether, 2 ether);
    }

    function test_enableMint() public {
        vm.expectRevert(abi.encodePacked("Already enabled"));
        nft.enableMint();

        BrewlabsFlaskNft _nft = new BrewlabsFlaskNft();

        vm.expectEmit(false, false, false, true);
        emit MintEnabled();
        _nft.enableMint();

        assertTrue(_nft.mintAllowed());
    }

    function test_setFeeToken() public {
        vm.expectRevert(abi.encodePacked("Invalid token"));
        nft.setFeeToken(address(0x0), true);

        vm.expectEmit(false, false, false, true);
        emit SetFeeToken(address(0x1), true);
        nft.setFeeToken(address(0x1), true);

        assertEq(nft.tokenAllowed(address(0x1)), true);
    }

    function test_setBrewlabsWallet() public {
        vm.expectRevert(abi.encodePacked("Invalid address"));
        nft.setBrewlabsWallet(address(0x0));

        vm.expectEmit(false, false, false, true);
        emit SetBrewlabsWallet(address(0x1));
        nft.setBrewlabsWallet(address(0x1));
    }

    function test_setStakingAddress() public {
        vm.expectRevert(abi.encodePacked("Invalid address"));
        nft.setStakingAddress(address(0x0));

        vm.expectEmit(false, false, false, true);
        emit SetStakingAddress(address(0x1));
        nft.setStakingAddress(address(0x1));
    }

    function test_setTokenBaseUri() public {
        vm.expectEmit(false, false, false, true);
        emit BaseURIUpdated("uri");
        nft.setTokenBaseUri("uri");
    }

    function test_addToWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(address(0x123), 3);
        nft.addToWhitelist(address(0x123), 3);

        assertEq(nft.whitelist(address(0x123)), 3);
    }

    function test_removeFromWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(address(0x123), 0);
        nft.removeFromWhitelist(address(0x123));

        assertEq(nft.whitelist(address(0x123)), 0);
    }

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
