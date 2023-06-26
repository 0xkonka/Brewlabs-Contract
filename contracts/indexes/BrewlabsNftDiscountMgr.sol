// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IBrewlabsNft {
    function rarityOf(uint256 tokenId) external view returns (uint256);
    function tBalanceOf(address owner) external view returns (uint256);
    function tTokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

contract BrewlabsNftDiscountMgr is Ownable {
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_DISCOUNT = 8000;

    address public nftCollection;
    mapping(uint256 => uint256) public discounts;

    uint256 public checkLimit = 30;
    uint256 private discountLength;

    event SetNftCollection(address nft);
    event SetCheckingLimit(uint256 limit);
    event SetDiscountValues(uint256[] discounts);
    event SetDiscountValue(uint256 rarity, uint256 discount);

    constructor() {}

    function discountOf(address _user) external view returns (uint256) {
        if (nftCollection == address(0x0)) return 0;

        uint256 balance = IBrewlabsNft(nftCollection).tBalanceOf(_user);
        if (balance == 0) return 0;

        uint256 maxRarity = 0;
        for (uint256 i = 0; i < balance; i++) {
            if (i >= checkLimit) break;
            uint256 tokenId = IBrewlabsNft(nftCollection).tTokenOfOwnerByIndex(_user, i);
            uint256 rarity = IBrewlabsNft(nftCollection).rarityOf(tokenId);

            if (maxRarity < rarity) maxRarity = rarity;
        }
        return maxRarity > 0 ? discounts[maxRarity - 1] : 0;
    }

    function setCollection(address _nft) external onlyOwner {
        nftCollection = address(_nft);
        emit SetNftCollection(nftCollection);
    }

    function setCheckingLimit(uint256 _limit) external onlyOwner {
        checkLimit = _limit;
        emit SetCheckingLimit(_limit);
    }

    function setDiscounts(uint256[] memory _discounts) external onlyOwner {
        // update discount config
        for (uint256 i = 0; i < _discounts.length; i++) {
            require(_discounts[i] <= MAX_DISCOUNT, "Discount cannot exceed limit");
            discounts[i] = _discounts[i];
        }

        // reset previous settings
        for(uint256 i = _discounts.length; i < discountLength; i++) {
            discounts[i] = 0;
        }
        discountLength = _discounts.length;

        emit SetDiscountValues(_discounts);
    }

    function setDiscount(uint256 _rarity, uint256 _discount) external onlyOwner {
        require(_discount <= MAX_DISCOUNT, "Cannot exceed limit");

        discounts[_rarity] = _discount;
        emit SetDiscountValue(_rarity, _discount);
    }
}
