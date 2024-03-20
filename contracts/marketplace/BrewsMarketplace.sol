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

interface IOwnable {
    function owner() external view returns (address);
}

contract BrewsMarketplace is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC1155ReceiverUpgradeable,
    IERC721ReceiverUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    // enum and struct definition
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
        // market price, precesion 18
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
        // multiplier precalculated to calculate paid token amount
        uint256 multiplier;
    }

    struct Purchase {
        address buyer;
        // bought time
        uint96 boughtTime;
        // token amount to purchase
        uint256 buyAmount;
        // claimed token amount of purchased
        uint256 claimed;
        // token amount paid to purchase
        uint256 paidTokenAmount;
        // claimed amount of paid
        uint256 claimedPaidToken;
    }
    // constants
    // function selectors
    bytes4 private constant ERC1155_ACCEPTED = 0xf23a6e61; // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
    bytes4 private constant ERC1155_BATCH_ACCEPTED = 0xbc197c81; // bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02; //bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    uint256 private constant PERCENT_PRECISION = 10000;
    uint256 private constant MAX_FEE = 2000;
    uint256 private constant MAX_ROYALTY_FEE = 500;

    // variables
    uint256 public marketCount;
    // limit for vestingTimes;
    uint256 private _maxVestingDays;
    // performance ether fee amount
    uint256 private _performanceFee;
    // treasury address
    address private _treasury;
    // purchase fee percent
    uint256 private _purchaseFee;

    // market info by address
    mapping(uint256 => MarketInfo) private markets;
    // purchases by market id
    mapping(uint256 => mapping(uint256 => Purchase)) private purchases;
    // minimum amounts by token address
    mapping(address => uint256) public minAmounts;
    // whitelist for sell tokens
    mapping(address => bool) public bSellTokens;
    // whitelist for tokens paid to purchase
    mapping(address => bool) public bPaidTokens;
    // royalty fee
    mapping(address => uint256) public royaltyFees;
    // royalty fee address
    mapping(address => address) public royaltyFeeAddresses;

    // events
    event ListEvent(
        uint256 indexed marketId,
        address indexed vendor,
        uint256 vestingDays,
        address token,
        uint256 price,
        uint256 amount,
        AssetType assetType,
        uint256 tokenId
    );
    event Delist(
        uint256 indexed marketId,
        address indexed vendor,
        uint256 indexed canceledAmount
    );
    event PurchaseEvent(
        uint256 indexed marketId,
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 amount,
        uint256 paidToken
    );
    event ClaimForBuyer(
        uint256 indexed marketId,
        uint256 indexed purchaseId,
        uint256 claimAmount
    );
    event ClaimForVendor(
        uint256 indexed marketId,
        uint256 indexed purchaseId,
        uint256 claimAmount
    );

    event EnableSellToken(address[] tokens, bool bEnable);
    event EnablePaidToken(address[] tokens, bool bEnable);
    event UpdateSetting(
        uint256 indexed maxVestingDays,
        uint256 indexed purchaseFee
    );
    event ServiceInfoChanged(address indexed addr, uint256 indexed fee);

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
        require(bSellTokens[sellToken], "invalid sell token");
        require(bPaidTokens[paidToken], "invalid paid token");
        require(vestingDays <= _maxVestingDays, "invalid vesting days");
        _transferPerformanceFee();
        uint8 sellTokenDecimals;
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
            sellTokenDecimals = IERC20MetadataUpgradeable(sellToken).decimals();
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
        require(sellAmount >= minAmounts[sellToken], "invalid amount");
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
            tokenId: tokenId,
            multiplier: 10 **
                (18 -
                    IERC20MetadataUpgradeable(paidToken).decimals() +
                    sellTokenDecimals)
        });
        markets[marketCount] = m;
        emit ListEvent(
            marketCount,
            msg.sender,
            vestingDays,
            sellToken,
            price,
            sellAmount,
            assetType,
            tokenId
        );
    }

    function delist(uint256 marketId) external nonReentrant {
        MarketInfo memory m = markets[marketId];
        require(m.vendor == msg.sender, "no vendor");
        require(m.reserve > 0, "no remaining token");

        markets[marketId].reserve = 0;
        _withdrawListedAsset(
            m.sellToken,
            m.vendor,
            m.reserve,
            m.assetType,
            m.tokenId
        );

        emit Delist(marketId, m.vendor, m.reserve);
    }

    /**
     * @notice buyer purchase listed token
     * @param marketId market id
     * @param amount token amount to purchase
     */
    function purchase(
        uint256 marketId,
        uint256 amount
    ) external payable nonReentrant {
        _transferPerformanceFee();
        MarketInfo memory market = markets[marketId];
        require(market.reserve >= amount, "insufficient listed amount");
        unchecked {
            markets[marketId].reserve = market.reserve - amount;
        }
        uint256 paidTokenAmount = (amount * market.price) / market.multiplier;
        require(paidTokenAmount > 0, "small amount");
        uint256 fee = (_purchaseFee * paidTokenAmount) / PERCENT_PRECISION;
        // apply royalty for NFT purchase
        if (
            market.assetType != AssetType.ERC20 &&
            royaltyFees[market.sellToken] > 0
        ) {
            uint256 royaltyFeeAmount = (royaltyFees[market.sellToken] *
                paidTokenAmount) / PERCENT_PRECISION;
            IERC20Upgradeable(market.paidToken).safeTransferFrom(
                msg.sender,
                royaltyFeeAddresses[market.sellToken],
                royaltyFeeAmount
            );
            unchecked {
                paidTokenAmount = paidTokenAmount - royaltyFeeAmount - fee;
            }
        } else {
            unchecked {
                paidTokenAmount -= fee;
            }
        }

        uint256 claimed;
        uint256 claimedPaidToken;
        address to = address(this);
        if (market.vestingTime == 0) {
            _withdrawListedAsset(
                market.sellToken,
                msg.sender,
                amount,
                market.assetType,
                market.tokenId
            );
            claimed = amount;
            claimedPaidToken = paidTokenAmount;
            // transfer paid token to vendor in the case of constant bond
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
        emit PurchaseEvent(
            marketId,
            markets[marketId].purchaseCount,
            msg.sender,
            amount,
            paidTokenAmount
        );
    }

    /**
     * @notice buyer claim purchased token
     * @param marketId market id
     * @param purchaseId purchase id
     */
    function claimForBuyer(
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
        require(claimable > 0, "can't claim");
        _withdrawListedAsset(
            m.sellToken,
            msg.sender,
            claimable,
            m.assetType,
            m.tokenId
        );
        purchases[marketId][purchaseId].claimed = p.claimed + claimable;
        emit ClaimForBuyer(marketId, purchaseId, claimable);
    }

    /**
     * @notice vendor claim token that buyer paid to purchase
     * @param marketId market id
     * @param purchaseId purchase id
     */
    function claimForVendor(
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
        require(claimable > 0, "can't claim");
        IERC20Upgradeable(m.paidToken).safeTransfer(msg.sender, claimable);
        purchases[marketId][purchaseId].claimedPaidToken =
            p.claimedPaidToken +
            claimable;

        emit ClaimForVendor(marketId, purchaseId, claimable);
    }

    function getMarket(
        uint256 marketId
    ) external view returns (MarketInfo memory) {
        return markets[marketId];
    }

    function getPurchase(
        uint256 marketId,
        uint256 purchaseId
    )
        external
        view
        returns (
            Purchase memory p,
            uint256 claimable,
            uint256 claimablePaidToken
        )
    {
        p = purchases[marketId][purchaseId];
        MarketInfo memory m = markets[marketId];
        if (p.boughtTime + m.vestingTime <= block.timestamp) {
            claimable = p.buyAmount - p.claimed;
            claimablePaidToken = p.paidTokenAmount - p.claimedPaidToken;
        } else {
            claimable =
                (p.buyAmount * (block.timestamp - p.boughtTime)) /
                m.vestingTime -
                p.claimed;
            claimablePaidToken =
                (p.paidTokenAmount * (block.timestamp - p.boughtTime)) /
                m.vestingTime -
                p.claimedPaidToken;
        }
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
        emit EnableSellToken(sellTokens, bEnable);
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
        emit EnablePaidToken(paidTokens, bEnable);
    }

    function setMarketSetting(
        uint256 maxVestingDays,
        uint256 purchaseFee
    ) external onlyOwner {
        _maxVestingDays = maxVestingDays;
        require(purchaseFee <= MAX_FEE, "invalid purchase fee");
        _purchaseFee = purchaseFee;
        emit UpdateSetting(maxVestingDays, purchaseFee);
    }

    function setServiceInfo(address treasury, uint256 performanceFee) external {
        require(msg.sender == _treasury, "setServiceInfo: FORBIDDEN");
        require(treasury != address(0x0), "Invalid address");
        require(performanceFee >= 0.0035 ether, "Invalid fee");

        _treasury = treasury;
        _performanceFee = performanceFee;

        emit ServiceInfoChanged(treasury, performanceFee);
    }

    /**
     * @notice set royalty for ERC721 and ERC1155
     */
    function setRoyalty(
        address collection,
        address feeAddress,
        uint256 fee
    ) external {
        require(msg.sender == IOwnable(collection).owner(), "invalid owner");
        require(fee <= MAX_ROYALTY_FEE, "too big royalty");
        royaltyFeeAddresses[collection] = feeAddress;
        royaltyFees[collection] = fee;
    }

    function setMinAmounts(
        address token,
        uint256 minAmount
    ) external onlyOwner {
        minAmounts[token] = minAmount;
    }

    function _withdrawListedAsset(
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
