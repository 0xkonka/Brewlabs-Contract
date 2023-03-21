// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBrewlabsIndex {
  function initialize(
    IERC20[] memory tokens,
    IERC721 nft,
    address router,
    address[][] memory paths,
    address owner
  ) external;

  function fee() external view returns (address);

  function performanceFee() external view returns (address);

  function treasury() external view returns (address);

  function nft() external view returns (address);

  function NUM_TOKENS() external view returns (uint8);

  function tokens(uint256 index) external view returns (address);

  function userInfo(
    address user
  ) external view returns (uint256[] memory amounts, uint256 ethAmount);

  function nftInfo(uint256 tokenId) external view returns (uint256[] memory, uint256);

  function totalStaked(uint256 index) external view returns (uint256);

  function getSwapPath(uint8 index, bool isZapIn) external view returns (address[] memory);

  function zapIn(uint256[] memory percents) external payable;

  function zapOut() external;

  function claimTokens() external;

  function mintNft() external payable returns (uint256);

  function stakeNft(uint256 tokenId) external payable;

  function setSwapSettings(address router, address[][] memory paths) external;

  function setFee(uint256 fee) external;

  function setServiceInfo(address treasury, uint256 fee) external;

  function rescueTokens(address token) external;
}
