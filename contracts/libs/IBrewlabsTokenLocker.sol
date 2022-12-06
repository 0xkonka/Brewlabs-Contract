// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBrewlabsTokenLocker {
    function NONCE() external view returns (uint256);

    function editFee() external view returns (uint256);
    function defrostFee() external view returns (uint256);
    function token() external view returns (address);
    function reflectionToken() external view returns (address);
    function totalLocked() external view returns (uint256);
    function treasury() external view returns (address);

    struct TokenLock {
        uint256 lockID; // lockID nonce per token
        uint256 lockDate; // the date the token was locked
        uint256 amount; // the amount of tokens still locked
        uint256 unlockTime; // the date the token can be withdrawn
        uint256 unlockRate; // 0 - not vesting, else - vesting
        address operator;
        uint256 tokenDebt;
        uint256 reflectionDebt;
        bool isDefrost;
    }

    function locks(uint256 index) external view returns (TokenLock memory);
    function pendingReflections(address _user) external view returns (uint256 pending);
    function pendingClaims(uint256 _lockID) external view returns (uint256);

    // owner method
    function initialize(
        address _token,
        address _reflectionToken,
        address _treasury,
        uint256 _editFee,
        uint256 _defrostFee,
        address _devWallet,
        uint256 _devRate,
        address _owner
    ) external;
    function defrost(uint256 _lockID) external;
    function newLock(address _operator, uint256 _amount, uint256 _unlockTime, uint256 _unlockRate) external;
    function setTreasury(address _treasury) external;
    function transferOwnership(address newOwner) external;

    // operator method
    function addLock(uint256 _lockID, uint256 _amount) external payable;
    function allowDefrost(uint256 _lockID) external payable;
    function claim(uint256 _lockID) external;
    function harvest(uint256 _lockID) external payable;
    function reLock(uint256 _lockID, uint256 _unlockTime) external payable;
    function splitLock(uint256 _lockID, address _operator, uint256 _amount, uint256 _unlockTime) external payable;
    function transferLock(uint256 _lockID, address _operator) external payable;
}
