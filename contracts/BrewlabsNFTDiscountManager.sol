// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IBrewlabsNft {
    function rarityOf(uint256 tokenId) external view returns (uint256);
    function tBalanceOf(address owner) external view returns (uint256);
    function tTokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

contract BrewlabsNftDiscountMgr is Ownable {
    uint256 public constant MAX_DISCOUNT = 8000;

    address public nftCollection;
    mapping(uint256 => uint256) public discounts;
    mapping(address => bool) public whitelist;

    uint256 public checkLimit = 30;
    uint256 private discountLength;

    event SetNftCollection(address nft);
    event SetCheckingLimit(uint256 limit);
    event SetDiscountValues(uint256[] discounts);
    event SetDiscountValue(uint256 rarity, uint256 discount);
    event Whitelisted(address indexed addr, bool status);

    constructor() {}

    function discountOf(address _user) external view returns (uint256) {
        if (nftCollection == address(0x0)) return 0;
        if (isContract(_user) && !whitelist[_user]) return 0;

        uint256 balance = IBrewlabsNft(nftCollection).tBalanceOf(_user);
        if (balance == 0) return 0;

        uint256 maxRarity = 0;
        uint256 _checkLimit = checkLimit;
        uint256 length = balance < _checkLimit ? balance : _checkLimit;
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = IBrewlabsNft(nftCollection).tTokenOfOwnerByIndex(_user, i);
            uint256 rarity = IBrewlabsNft(nftCollection).rarityOf(tokenId);

            if (maxRarity < rarity) maxRarity = rarity;
        }

        uint256 _discountLength = discountLength;
        return maxRarity > 0 && _discountLength > 0
            ? maxRarity > _discountLength ? discounts[_discountLength - 1] : discounts[maxRarity - 1]
            : 0;
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
        uint256 _discountLength = _discounts.length;
        require(_discountLength > 0, "Invalid discounts");

        // update discount config
        uint256 lastDiscount;
        for (uint256 i = 0; i < _discountLength; i++) {
            require(_discounts[i] <= MAX_DISCOUNT, "Discount cannot exceed limit");
            require(_discounts[i] >= lastDiscount, "Invalid discount order");
            discounts[i] = _discounts[i];
            lastDiscount = _discounts[i];
        }

        // reset previous settings
        for (uint256 i = _discountLength; i < discountLength; ++i) {
            discounts[i] = 0;
        }
        discountLength = _discountLength;

        emit SetDiscountValues(_discounts);
    }

    function setDiscount(uint256 _rarity, uint256 _discount) external onlyOwner {
        require(_discount <= MAX_DISCOUNT, "Cannot exceed limit");

        discounts[_rarity] = _discount;
        emit SetDiscountValue(_rarity, _discount);
    }

    function setWhitelist(address addr, bool status) external onlyOwner {
        require(addr != address(0), "Brewlabs: invalid address");
        whitelist[addr] = status;
        emit Whitelisted(addr, status);
    }

    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}
