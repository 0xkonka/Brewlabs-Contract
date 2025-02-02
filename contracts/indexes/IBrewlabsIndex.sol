// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IBrewlabsAggregator} from "../libs/IBrewlabsAggregator.sol";

interface IBrewlabsIndex {
    function initialize(
        string memory name,
        IERC20[] memory tokens,
        IERC721 indexNft,
        IERC721 deployerNft,
        uint256[2] memory fees,
        address owner,
        address deployer,
        address commissionWallet
    ) external;

    function name() external view returns (string memory);
    function factory() external view returns (address);
    function indexNft() external view returns (address);
    function deployerNft() external view returns (address);

    function NUM_TOKENS() external view returns (uint256);
    function tokens(uint256 index) external view returns (address);

    function owner() external view returns (address);
    function deployer() external view returns (address);
    function deployerNftId() external view returns (uint256);

    function depositFee() external view returns (uint256);
    function commissionFee() external view returns (uint256);
    function performanceFee() external view returns (uint256);
    function treasury() external view returns (address);
    function commissionWallet() external view returns (address);

    function swapAggregator() external view returns (address);

    function userInfo(address user) external view returns (uint256[] memory amounts, uint256 usdAmount);
    function nftInfo(uint256 tokenId)
        external
        view
        returns (uint256 level, uint256[] memory amounts, uint256 usdAmount);
    function estimateEthforUser(address user) external view returns (uint256);
    function estimateEthforNft(uint256 tokenId) external view returns (uint256);
    function totalStaked(uint256 index) external view returns (uint256);

    function getPriceFromChainlink() external view returns (uint256);
    function getPendingCommissions() external view returns (uint256[] memory);
    function totalCommissions() external view returns (uint256);

    function precomputeZapIn(address token, uint256 amount, uint256[] memory percents)
        external
        view
        returns (IBrewlabsAggregator.FormattedOffer[] memory queries);
    function precomputeZapOut(address token)
        external
        view
        returns (IBrewlabsAggregator.FormattedOffer[] memory queries);

    function zapIn(address token, uint256 amount, uint256[] memory percents, IBrewlabsAggregator.Trade[] memory trades)
        external
        payable;
    function zapOut(address token, IBrewlabsAggregator.Trade[] memory trades) external;
    function claimTokens(uint256 percent, IBrewlabsAggregator.Trade[] memory _trades) external;
    function mintNft() external payable returns (uint256);
    function stakeNft(uint256 tokenId) external payable;

    function mintDeployerNft() external payable returns (uint256);
    function stakeDeployerNft() external payable;
    function unstakeDeployerNft() external payable;

    function setIndexNft(IERC721 newNftAddr) external;
    function setDeployerNft(IERC721 newNftAddr) external;
    function setFeeSettings(uint256[2] memory fees, address feeWallet) external payable;
    function setSwapAggregator(address aggregator) external;

    function setServiceInfo(address treasury, uint256 fee) external;
    function rescueTokens(address token) external;

    function transferOwnership(address newOwner) external;
}
