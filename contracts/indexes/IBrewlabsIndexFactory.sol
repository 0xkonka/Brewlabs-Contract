// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBrewlabsIndexFactory {
    function initialize(
        address impl,
        IERC721 indexNft,
        IERC721 deployerNft,
        IERC20 token,
        uint256 price,
        address indexOwner
    ) external;
    function createBrewlabsIndex(
        string memory indexName,
        address[] memory tokens,
        uint256 fee,
        address feeWallet,
        bool isPrivate
    ) external payable returns (address index);

    function version(uint256 category) external view returns (uint256);
    function implementation(uint256 category) external view returns (address);

    function indexNft() external view returns (address);
    function deployerNft() external view returns (address);
    function indexDefaultOwner() external view returns (address);

    function payingToken() external view returns (address);
    function serviceFee() external view returns (uint256);
    function treasury() external view returns (address);

    function brewlabsFee() external view returns (uint256);
    function brewlabsWallet() external view returns (address);
    function feeLimit() external view returns (uint256);

    function discountMgr() external view returns (address);

    function indexCount() external view returns (uint256);
    function getIndexInfo(uint256 idx)
        external
        view
        returns (
            address indexAddr,
            address name,
            uint256 category,
            address indexNft,
            address deployerNft,
            address[] memory tokens,
            address deployer,
            uint256 createdAt
        );
    function allowedTokens(address token) external view returns (uint8);
    function wrappers(address token) external view returns (address);
    function whitelist(address addr) external view returns (bool);

    function setImplementation(uint256 category, address impl) external;
    function setIndexNft(IERC721 nft) external;
    function setDeployerNft(IERC721 nft) external;
    function setIndexOwner(address newOwner) external;
    function setDiscountManager(address addr) external;

    function setBrewlabsFee(uint256 fee) external;
    function setBrewlabsWallet(address wallet) external;
    function setIndexFeeLimit(uint256 limit) external;
    function setAllowedToken(address token, uint8 flag, address wrapper) external;

    function setServiceFee(uint256 fee) external;
    function setPayingToken(address token) external;
    function addToWhitelist(address addr) external;
    function removeFromWhitelist(address addr) external;

    function setTreasury(address treasury) external;
    function rescueTokens(address token) external;

    function transferOwnership(address newOwner) external;
}
