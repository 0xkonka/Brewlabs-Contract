// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBrewlabsFarmFactory {
    function initialize(address impl, address token, uint256 price, address farmOwner) external;
    function createBrewlabsFarm(
        IERC20 lpToken,
        IERC20 rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend
    ) external payable returns (address farm);

    function version(uint256 category) external view returns (uint256);
    function implementation(uint256 category) external view returns (address);

    function farmDefaultOwner() external view returns (address);

    function payingToken() external view returns (address);
    function serviceFee() external view returns (uint256);
    function performanceFee() external view returns (uint256);
    function treasury() external view returns (address);

    function farmCount() external view returns (uint256);
    function farmInfo(uint256 idx)
        external
        view
        returns (
            address farm,
            uint256 category,
            uint256 version,
            address lpToken,
            address rewardToken,
            address dividendToken,
            bool hasDividend,
            address deployer,
            uint256 createdAt
        );
    function whitelist(address addr) external view returns (bool);

    function setImplementation(uint256 category, address impl) external;
    function setFarmOwner(address newOwner) external;

    function setServiceFee(uint256 fee) external;
    function setPayingToken(address token) external;
    function addToWhitelist(address addr) external;
    function removeFromWhitelist(address addr) external;

    function setTreasury(address treasury) external;
    function rescueTokens(address token) external;
}
