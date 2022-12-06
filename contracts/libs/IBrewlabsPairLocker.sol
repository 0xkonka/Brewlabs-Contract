// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrewlabsPairLocker {
    function NONCE() external view returns (uint256);

    function defrostFee() external view returns (uint256);
    function editFee() external view returns (uint256);
    function lpToken() external view returns (address);
    function totalLocked() external view returns (uint256);
    function treasury() external view returns (address);

    struct PairLock {
        uint256 lockID; // lockID nonce per uni pair
        uint256 lockDate; // the date the token was locked
        uint256 amount; // the amount of tokens still locked
        uint256 unlockTime; // the date the token can be withdrawn
        address operator;
        uint256 tokenDebt;
        bool isDefrost;
    }

    function locks(uint256 index) external view returns (PairLock memory);

    // owner method
    function initialize(
        address _lpToken,
        address _treasury,
        uint256 _editFee,
        uint256 _defrostFee,
        address _devWallet,
        uint256 _devPercent,
        address _owner
    ) external;
    function defrost(uint256 _lockID) external;
    function newLock(address _operator, uint256 _amount, uint256 _unlockTime) external;
    function setTreasury(address _treasury) external;
    function transferOwnership(address newOwner) external;

    // operator method
    function addLock(uint256 _lockID, uint256 _amount) external payable;
    function allowDefrost(uint256 _lockID) external payable;
    function claim(uint256 _lockID) external;
    function reLock(uint256 _lockID, uint256 _unlockTime) external payable;
    function splitLock(uint256 _lockID, address _operator, uint256 _amount, uint256 _unlockTime) external payable;
    function transferLock(uint256 _lockID, address _operator) external payable;
}
