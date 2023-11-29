// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBrewlabsTokenFactory {
    function initialize(address impl, address token, uint256 price, address treasuryWallet) external;

    function createBrewlabsStandardToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply
    ) external payable returns (address token);

    function version(uint256 category) external view returns (uint256);
    function implementation(uint256 category) external view returns (address);

    function payingToken() external view returns (address);
    function serviceFee() external view returns (uint256);
    function treasury() external view returns (address);

    function tokenCount() external view returns (uint256);
    function tokenInfo(uint256 idx) external view returns(address token,
        uint256 category,
        uint256 version,
        string memory name,
        string memory symbol,
        uint8   decimals,
        uint256 totalSupply,
        address deployer,
        uint256 createdAt);
    function whitelist(address addr) external view returns (bool);

    function setImplementation(uint256 category, address impl) external;
    function setServiceFee(uint256 fee) external;
    function setPayingToken(address token) external;
    function addToWhitelist(address _addr) external;
    function removeFromWhitelist(address _addr) external;
    function setTreasury(address newTreasury) external;
    function rescueTokens(address _token) external;
}
