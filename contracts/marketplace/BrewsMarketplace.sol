// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BrewlabsMarketplace is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct TokenGroup {
        // token addresses
        address[] addresses;
        bytes32 groupName;
    }

    struct MarketInfo {
        // listed token address
        address sellToken;
        // vesting time
        uint96 vestingTime;
        // seller address
        address seller;
        uint96 startTime;
        // listed price, precision 18
        uint256 price;
        // sell amount
        uint256 sellAmount;
        // remain amount
        uint256 reserve;
        // purchase count
        uint256 purchaseCount;
    }

    struct Purchase {
        address buyer;
        uint96 boughtTime;
        uint256 buyAmount;
        uint256 claimed;
    }

    // variables
    uint32[] vestingPeriods;
    uint256 marketCount;
    // market info by address
    mapping(uint256 => MarketInfo) markets;
    // purchases by market id
    mapping(uint256 => mapping(uint256 => Purchase)) purchases;
    // minimum amounts by token address
    mapping(address => uint256) minAmounts;

    constructor() {}

    function initialize() external initializer {
        __Ownable_init();
        vestingPeriods = [0, 2 days, 3 days, 5 days];
    }

    function listToken(MarketInfo memory marketInfo) external payable {
        require(marketInfo.sellToken != address(0), "invalid token");
        require(marketInfo.price != 0, "invalid price");
        require(
            marketInfo.sellAmount >= minAmounts[marketInfo.sellToken],
            "invalid price"
        );
        marketCount++;
        marketInfo.startTime = uint96(block.timestamp);
        marketInfo.seller = msg.sender;
        marketInfo.purchaseCount = 0;
        markets[marketCount] = marketInfo;

        IERC20(marketInfo.sellToken).safeTransferFrom(
            msg.sender,
            address(this),
            marketInfo.sellAmount
        );
    }

    function purchase(uint256 marketId, uint256 amount) external {
        MarketInfo memory market = markets[marketId];
        require(market.reserve >= amount, "insufficient listed amount");
        markets[marketId].reserve -= amount;

        Purchase memory p = Purchase({
            buyer: msg.sender,
            buyAmount: amount,
            claimed: 0,
            boughtTime: uint96(block.timestamp)
        });
        ++markets[marketId].purchaseCount;
        purchases[marketId][markets[marketId].purchaseCount] = p;
    }

    function claimPurchase(uint256 marketId, uint256 purchaseId) external {
        Purchase memory p = purchases[marketId][purchaseId];
        MarketInfo memory m = markets[marketId];
        require(p.buyer == msg.sender, "invalid buyer");
        uint256 claimable;
        if (p.boughtTime + m.vestingTime >= block.timestamp) {
            claimable = p.buyAmount - p.claimed;
        } else {
            claimable =
                (p.buyAmount * (block.timestamp - p.boughtTime)) /
                m.vestingTime -
                p.claimed;
        }
        IERC20(m.sellToken).safeTransferFrom(
        msg.sender,
            address(this),
            claimable
        );
        purchases[marketId][purchaseId].claimed = p.claimed + claimable;
    }    

    // check if address is contract
    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /**
     * @notice Emergency withdraw tokens.
     * @param _token: token address
     */
    function rescueTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            uint256 _ethAmount = address(this).balance;
            payable(msg.sender).transfer(_ethAmount);
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }
    
    receive() external payable {}
}
