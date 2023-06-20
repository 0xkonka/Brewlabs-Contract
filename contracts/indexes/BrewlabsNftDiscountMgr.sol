// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721, IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IBrewlabsNft {
    function rarityOf(uint256 tokenId) external view returns (uint256);
}

contract BrewlabsNftDiscountMgr is Ownable {
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_DISCOUNT = 8000;

    address public nftCollection;
    mapping(uint256 => uint256) public discounts;

    uint256 public checkLimit = 30;

    event SetNftCollection(address nft);
    event SetCheckingLimit(uint256 limit);
    event SetDiscountValues(uint256[] discounts);
    event SetDiscountValue(uint256 rarity, uint256 discount);

    constructor() {}

    function discountOf(address _user) external view returns (uint256) {
        if (nftCollection == address(0x0)) return 0;

        uint256 balance = IERC721(nftCollection).balanceOf(_user);
        if (balance == 0) return 0;

        uint256 maxRarity = 0;
        for (uint256 i = 0; i < balance; i++) {
            if (i >= checkLimit) break;
            uint256 tokenId = IERC721Enumerable(nftCollection).tokenOfOwnerByIndex(_user, i);
            uint256 rarity = IBrewlabsNft(nftCollection).rarityOf(tokenId);

            if (maxRarity < rarity) maxRarity = rarity;
        }
        return maxRarity > 0 ?  discounts[maxRarity - 1] : 0;
    }

    function setCollection(IERC721 _nft) external onlyOwner {
        nftCollection = address(_nft);
        emit SetNftCollection(nftCollection);
    }

    function setCheckingLimit(uint256 _limit) external onlyOwner {
        checkLimit = _limit;
        emit SetCheckingLimit(_limit);
    }

    function setDiscounts(uint256[] memory _discounts) external onlyOwner {
        for (uint256 i = 0; i < _discounts.length; i++) {
            require(_discounts[i] <= MAX_DISCOUNT, "Discount cannot exceed limit");
            discounts[i] = _discounts[i];
        }
        emit SetDiscountValues(_discounts);
    }

    function setDiscount(uint256 _rarity, uint256 _discount) external onlyOwner {
        require(_discount <= MAX_DISCOUNT, "Cannot exceed limit");

        discounts[_rarity] = _discount;
        emit SetDiscountValue(_rarity, _discount);
    }
}
