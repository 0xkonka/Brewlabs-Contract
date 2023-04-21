// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBrewlabsIndexFactory {
    function initialize(address impl, IERC721 nft, address token, uint256 price, address indexOwner) external;
    function createBrewlabsIndex(IERC20[] memory tokens, address swapRouter, address[][] memory swapPaths)
        external
        payable
        returns (address index);

    function version() external view returns (uint256);
    function implementation() external view returns (address);

    function indexNft() external view returns (address);
    function indexDefaultOwner() external view returns (address);

    function payingToken() external view returns (address);
    function serviceFee() external view returns (uint256);
    function performanceFee() external view returns (uint256);
    function treasury() external view returns (address);

    function indexCount() external view returns (uint256);
    function getIndexInfo(uint256 idx)
        external
        view
        returns (
            address indexAddr,
            IERC721 nft,
            IERC20[] memory tokens,
            address swapRouter,
            address deployer,
            uint256 createdAt
        );
    function whitelist(address addr) external view returns (bool);

    function setImplementation(address impl) external;
    function setIndexNft(IERC721 nft) external;
    function setIndexOwner(address newOwner) external;

    function setServiceFee(uint256 fee) external;
    function setPayingToken(address token) external;
    function addToWhitelist(address addr) external;
    function removeFromWhitelist(address addr) external;

    function setTreasury(address treasury) external;
    function rescueTokens(address token) external;
}
