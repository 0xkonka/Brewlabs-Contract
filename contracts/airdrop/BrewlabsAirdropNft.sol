// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IBrewlabsDiscountManager} from "../libs/IBrewlabsDiscountManager.sol";

contract BrewlabsAirdropNft is Ownable {
    uint256 public constant DISCOUNT_MAX = 10_000;

    uint256 public commission = 0.00066 ether;
    uint256 public commissionLimit = 3 ether;
    uint256 public maxTxLimit = 200;

    /* options for 50% discount */
    address[] private tokensForDiscount;

    /* list of addresses for no fee */
    address[] private whitelist;

    address discountMgr;
    address public feeAddress = 0x408c4aDa67aE1244dfeC7D609dea3c232843189A;

    /* events */
    event AddedToWhitelist(address addr);
    event RemovedFromWhitelist(address addr);

    event AddedToDicountList(address token);
    event RemovedFromDicountList(address token);

    event DiscountMgrUpdated(address addr);
    event FeeAddressUpdated(address addr);

    event CommissionUpdated(uint256 amount);
    event CommissionLimitUpdated(uint256 amount);
    event CommissionTxLimitUpdated(uint256 amount);

    constructor() {}

    /* Airdrop Begins */
    function multiTransfer(address token, address[] calldata addresses, uint256[] calldata tokenIds) external payable {
        require(token != address(0x0), "Invalid token");
        require(addresses.length <= maxTxLimit, "GAS Error: max airdrop limit is 200 addresses");
        require(addresses.length == tokenIds.length, "Mismatch between address and tokenId");

        for (uint256 i = 0; i < addresses.length; i++) {
            IERC721(token).safeTransferFrom(msg.sender, addresses[i], tokenIds[i]);
        }

        uint256 fee = estimateServiceFee(token, addresses.length);
        if (fee > 0) {
            require(msg.value == fee, "must send correct fee");

            payable(feeAddress).transfer(fee);
        }
    }

    function estimateServiceFee(address token, uint256 count) public view returns (uint256) {
        if (isInWhitelist(msg.sender)) return 0;

        uint256 fee = commission * count;
        if (fee > commissionLimit) fee = commissionLimit;

        if (isInDiscountList(token)) return fee / 2;

        if (discountMgr != address(0)) {
            uint256 discount = IBrewlabsDiscountManager(discountMgr).discountOf(msg.sender);
            fee = fee * (DISCOUNT_MAX - discount) / DISCOUNT_MAX;
        }
        return fee;
    }

    function addToDiscount(address token) external onlyOwner {
        require(token != address(0x0), "Invalid address");
        require(isInDiscountList(token) == false, "Already added to token list for discount");

        tokensForDiscount.push(token);

        emit AddedToDicountList(token);
    }

    function removeFromDiscount(address token) external onlyOwner {
        require(token != address(0x0), "Invalid address");
        require(isInDiscountList(token) == true, "Not exist in token list for discount");

        for (uint256 i = 0; i < tokensForDiscount.length; i++) {
            if (tokensForDiscount[i] == token) {
                tokensForDiscount[i] = tokensForDiscount[tokensForDiscount.length - 1];
                tokensForDiscount[tokensForDiscount.length - 1] = address(0x0);
                tokensForDiscount.pop();
                break;
            }
        }

        emit RemovedFromDicountList(token);
    }

    function isInDiscountList(address token) public view returns (bool) {
        for (uint256 i = 0; i < tokensForDiscount.length; i++) {
            if (tokensForDiscount[i] == token) {
                return true;
            }
        }

        return false;
    }

    function addToWhitelist(address addr) external onlyOwner {
        require(addr != address(0x0), "Invalid address");
        require(isInWhitelist(addr) == false, "Already added to whitelsit");

        whitelist.push(addr);

        emit AddedToWhitelist(addr);
    }

    function removeFromWhitelist(address addr) external onlyOwner {
        require(addr != address(0x0), "Invalid address");
        require(isInWhitelist(addr) == true, "Not exist in whitelist");

        for (uint256 i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == addr) {
                whitelist[i] = whitelist[whitelist.length - 1];
                whitelist[whitelist.length - 1] = address(0x0);
                whitelist.pop();
                break;
            }
        }

        emit RemovedFromWhitelist(addr);
    }

    function isInWhitelist(address addr) public view returns (bool) {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == addr) {
                return true;
            }
        }

        return false;
    }

    function setFeeAddress(address addr) external onlyOwner {
        require(addr != address(0x0), "Invalid address");

        feeAddress = addr;

        emit FeeAddressUpdated(addr);
    }

    function setDiscountMgrAddress(address addr) external onlyOwner {
        require(addr == address(0) || isContract(addr), "Invalid discount manager");
        discountMgr = addr;

        emit DiscountMgrUpdated(addr);
    }

    function setCommission(uint256 _commission) external onlyOwner {
        require(_commission > 0, "Invalid amount");
        commission = _commission;

        emit CommissionUpdated(_commission);
    }

    function setCommissionLimit(uint256 _limit) external onlyOwner {
        require(_limit > 0, "Invalid amount");
        commissionLimit = _limit;

        emit CommissionLimitUpdated(_limit);
    }

    function setMaxTxLimit(uint256 _txLimit) external onlyOwner {
        require(_txLimit > 0, "Invalid amount");
        maxTxLimit = _txLimit;

        emit CommissionTxLimitUpdated(_txLimit);
    }

    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}
