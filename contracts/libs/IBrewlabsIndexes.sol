// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBrewlabsIndexes {
    function initialize(
        IERC20[] memory _tokens,
        IERC721 _nft,
        address _router,
        address[][] memory _paths,
        address _owner
    ) external;

    function fee() external view returns (address);
    function performanceFee() external view returns (address);
    function treasury() external view returns (address);

    function nft() external view returns (address);
    function NUM_TOKENS() external view returns (uint8);
    function tokens(uint256 index) external view returns (address);

    function userInfo(address _user) external view returns (uint256[] memory amounts, uint256 ethAmount);
    function nftInfo(uint256 _tokenId) external view returns (uint256[] memory, uint256);
    function totalStaked(uint256 index) external view returns (uint256);

    function getSwapPath(uint8 _type, uint8 _index) external view returns (address[] memory);

    function buyTokens(uint256[] memory _percents) external payable;
    function claimTokens() external payable;
    function saleTokens() external payable;
    function lockTokens() external payable returns (uint256);
    function unlockTokens(uint256 tokenId) external payable;

    function setSwapSettings(address _router, address[][] memory _paths) external;
    function setFee(uint256 _fee) external;
    function setServiceInfo(address _addr, uint256 _fee) external;
    function rescueTokens(address _token) external;
}
