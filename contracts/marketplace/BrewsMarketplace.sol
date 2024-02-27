// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20MetadataUpgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1155Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721Upgradeable.sol";
import {IERC1155ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1155ReceiverUpgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol";

contract BrewsMarketplace is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC1155ReceiverUpgradeable,
    IERC721ReceiverUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum AssetType {
        ERC20,
        ERC721,
        ERC1155
    }
    struct MarketInfo {
        // token address listed on market
        address sellToken;
        // vesting time
        uint96 vestingTime;
        // vendor address
        address vendor;
        // listed time
        uint96 listedTime;
        // listed price, precesion 18
        uint256 price;
        // sell amount
        uint256 sellAmount;
        // remain amount
        uint256 reserve;
        // purchase count
        uint256 purchaseCount;
        // paid token address
        address paidToken;
        // asset type
        AssetType assetType;
        // token id in the case of nft
        uint256 tokenId;
    }

    struct Purchase {
        address buyer;
        uint96 boughtTime;
        // sell token amount
        uint256 buyAmount;
        uint256 claimed;
        // token amount paid to purchase
        uint256 paidTokenAmount;
        uint256 claimedPaidToken;
    }
    // constants
    // function selectors
    bytes4 private constant ERC1155_ACCEPTED = 0xf23a6e61; // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
    bytes4 private constant ERC1155_BATCH_ACCEPTED = 0xbc197c81; // bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02; //bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

    // variables
    uint256 marketCount;
    // market info by address
    mapping(uint256 => MarketInfo) markets;
    // purchases by market id
    mapping(uint256 => mapping(uint256 => Purchase)) purchases;
    // minimum amounts by token address
    mapping(address => uint256) minAmounts;
    // whitelist for sell tokens
    mapping(address => bool) bSellTokens;
    // whitelist for tokens paid to purchase
    mapping(address => bool) bPaidTokens;
    // limit for vestingTimes;
    uint256 internal _maxVestingDays;
    uint256 internal _performanceFee;
    address internal _treasury;
    uint256 internal _purchaseFee;
    uint256 constant PERCENT_PRECISION = 10000;
    // events
    event ListEvent(MarketInfo market);
    event PurchaseEvent(Purchase purchase);

    constructor() {}

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _maxVestingDays = 730;
        _performanceFee = 0.0035 ether;
        _treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        _purchaseFee = 30;
    }

    function listToken(
        address sellToken,
        uint256 vestingDays,
        uint256 price,
        uint256 sellAmount,
        address paidToken,
        AssetType assetType,
        uint256 tokenId
    ) external payable nonReentrant {
        require(price != 0, "invalid price");
        require(sellAmount >= minAmounts[sellToken], "invalid amount");
        require(bSellTokens[sellToken], "invalid sell token");
        require(bPaidTokens[paidToken], "invalid paid token");
        require(vestingDays <= _maxVestingDays, "invalid vesting days");
        _transferPerformanceFee();

        if (assetType == AssetType.ERC20) {
            uint256 beforeAmt = IERC20Upgradeable(sellToken).balanceOf(
                address(this)
            );
            IERC20Upgradeable(sellToken).safeTransferFrom(
                msg.sender,
                address(this),
                sellAmount
            );
            sellAmount =
                IERC20Upgradeable(sellToken).balanceOf(address(this)) -
                beforeAmt;
            tokenId = 0;
        } else if (assetType == AssetType.ERC721) {
            IERC721Upgradeable(sellToken).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                ""
            );
            sellAmount = 1;
        } else {
            IERC1155Upgradeable(sellToken).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                sellAmount,
                ""
            );
        }
        marketCount++;
        MarketInfo memory m = MarketInfo({
            sellToken: sellToken,
            vestingTime: uint96(vestingDays * 1 days),
            price: price,
            sellAmount: sellAmount,
            paidToken: paidToken,
            vendor: msg.sender,
            listedTime: uint96(block.timestamp),
            reserve: sellAmount,
            purchaseCount: 0,
            assetType: assetType,
            tokenId: tokenId
        });
        markets[marketCount] = m;
        emit ListEvent(m);
    }

    function purchase(
        uint256 marketId,
        uint256 amount
    ) external payable nonReentrant {
        _transferPerformanceFee();
        MarketInfo memory market = markets[marketId];
        require(market.reserve >= amount, "insufficient listed amount");
        markets[marketId].reserve -= amount;
        uint256 denominator = (10 **
            (18 -
                IERC20MetadataUpgradeable(market.paidToken).decimals() +
                IERC20MetadataUpgradeable(market.sellToken).decimals()));
        uint256 paidTokenAmount = (amount * market.price) / denominator;
        uint256 fee = (_purchaseFee * paidTokenAmount) / PERCENT_PRECISION;
        paidTokenAmount -= fee;

        uint256 claimed;
        uint256 claimedPaidToken;
        address to = address(this);
        if (market.vestingTime == 0) {
            _withrawListedAsset(
                market.sellToken,
                msg.sender,
                amount,
                market.assetType,
                market.tokenId
            );
            claimed = amount;
            claimedPaidToken = paidTokenAmount;
            // transfer to vendor for constant bond
            to = market.vendor;
        }
        IERC20Upgradeable(market.paidToken).safeTransferFrom(
            msg.sender,
            to,
            paidTokenAmount
        );
        IERC20Upgradeable(market.paidToken).safeTransferFrom(
            msg.sender,
            _treasury,
            fee
        );
        Purchase memory p = Purchase({
            buyer: msg.sender,
            buyAmount: amount,
            claimed: claimed,
            boughtTime: uint96(block.timestamp),
            paidTokenAmount: paidTokenAmount,
            claimedPaidToken: claimedPaidToken
        });
        ++markets[marketId].purchaseCount;
        purchases[marketId][markets[marketId].purchaseCount] = p;
        emit PurchaseEvent(p);
    }

    /**
     * @notice buyer claim purchased token
     * @param marketId market id
     * @param purchaseId purchase id
     */
    function claimPurchase(
        uint256 marketId,
        uint256 purchaseId
    ) external payable nonReentrant {
        _transferPerformanceFee();
        Purchase memory p = purchases[marketId][purchaseId];
        MarketInfo memory m = markets[marketId];
        require(p.buyer == msg.sender, "invalid buyer");
        uint256 claimable;
        if (p.boughtTime + m.vestingTime <= block.timestamp) {
            claimable = p.buyAmount - p.claimed;
        } else {
            claimable =
                (p.buyAmount * (block.timestamp - p.boughtTime)) /
                m.vestingTime -
                p.claimed;
        }
        _withrawListedAsset(
            m.sellToken,
            msg.sender,
            claimable,
            m.assetType,
            m.tokenId
        );
        purchases[marketId][purchaseId].claimed = p.claimed + claimable;
    }

    function claimPaidToken(
        uint256 marketId,
        uint256 purchaseId
    ) external payable nonReentrant {
        _transferPerformanceFee();
        Purchase memory p = purchases[marketId][purchaseId];
        MarketInfo memory m = markets[marketId];
        require(m.vendor == msg.sender, "invalid vendor");
        uint256 claimable;
        if (p.boughtTime + m.vestingTime <= block.timestamp) {
            claimable = p.paidTokenAmount - p.claimedPaidToken;
        } else {
            claimable =
                (p.paidTokenAmount * (block.timestamp - p.boughtTime)) /
                m.vestingTime -
                p.claimedPaidToken;
        }
        require(claimable > 0, "claimed all");
        IERC20Upgradeable(m.paidToken).safeTransfer(msg.sender, claimable);
        purchases[marketId][purchaseId].claimedPaidToken =
            p.claimedPaidToken +
            claimable;
    }

    function getMarket(
        uint256 marketId
    ) external view returns (MarketInfo memory) {
        return markets[marketId];
    }

    function getPurchase(
        uint256 marketId,
        uint256 purchaseId
    ) external view returns (Purchase memory) {
        return purchases[marketId][purchaseId];
    }

    function enableSellTokens(
        address[] calldata sellTokens,
        bool bEnable
    ) external onlyOwner {
        for (uint256 i; i < sellTokens.length; ) {
            bSellTokens[sellTokens[i]] = bEnable;
            unchecked {
                ++i;
            }
        }
    }

    function enablePaidTokens(
        address[] calldata paidTokens,
        bool bEnable
    ) external onlyOwner {
        for (uint256 i; i < paidTokens.length; ) {
            bPaidTokens[paidTokens[i]] = bEnable;
            unchecked {
                ++i;
            }
        }
    }

    function _withrawListedAsset(
        address token,
        address to,
        uint256 amount,
        AssetType assetType,
        uint256 tokenId
    ) internal {
        if (assetType == AssetType.ERC20) {
            IERC20Upgradeable(token).safeTransfer(to, amount);
        } else if (assetType == AssetType.ERC721) {
            IERC721Upgradeable(token).safeTransferFrom(
                address(this),
                to,
                tokenId,
                ""
            );
        } else {
            IERC1155Upgradeable(token).safeTransferFrom(
                address(this),
                to,
                tokenId,
                amount,
                ""
            );
        }
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= _performanceFee, "should pay small gas");

        payable(_treasury).transfer(_performanceFee);
        if (msg.value > _performanceFee) {
            payable(msg.sender).transfer(msg.value - _performanceFee);
        }
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure override returns (bytes4) {
        (operator);
        (from);
        (id);
        (value);
        (data); // solidity, be quiet please
        return ERC1155_ACCEPTED;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure override returns (bytes4) {
        (operator);
        (from);
        (ids);
        (values);
        (data); // solidity, be quiet please
        return ERC1155_BATCH_ACCEPTED;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        (operator);
        (from);
        (tokenId);
        (data); // solidity, be quiet please
        return ERC721_RECEIVED;
    }

    /**
     * @notice Emergency withdraw tokens.
     * @param _token: token address
     */
    function rescueTokens(address _token) external onlyOwner {
        require(
            !bSellTokens[_token] && !bPaidTokens[_token],
            "can't be sell or paid tokens"
        );
        if (_token == address(0x0)) {
            uint256 _ethAmount = address(this).balance;
            payable(msg.sender).transfer(_ethAmount);
        } else {
            uint256 _tokenAmount = IERC20Upgradeable(_token).balanceOf(
                address(this)
            );
            IERC20Upgradeable(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external view override returns (bool) {}

    receive() external payable {}
}
