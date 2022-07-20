// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrewlabsFreezer {
    struct FeeStruct {
        uint256 mintFee;
        uint256 editFee;
        uint256 defrostFee;
    }
    function gFees() external view returns(FeeStruct memory);
    
    function owner() external view returns(address);
    function implementation() external view returns(address);    

    function createTokenLocker(address _op, address _token, address _reflectionToken, uint256 _amount, uint256 _unlockTime, uint256 _cycle, uint256 _cAmount) external payable returns (address locker);
    function createLiquidityLocker(address _op, address _uniFactory, address _pair, uint256 _amount, uint256 _unlockTime) external payable returns (address locker);
    
    // owner methods
    function forceUnlockLP(address _locker, uint256 _lockID) external;
    function forceUnlockToken(address _locker, uint256 _lockID) external;
    function setFees(uint256 _mintFee, uint256 _editFee, uint256 _defrostFee) external;
    function setTreasury(address _treasury) external;
    function transferOwnership(address newOwner) external;

    function transferOwnershipOfLocker( address payable _locker, address _newOwner) external;
    function updateTreasuryOfLocker(address _locker, address _treasury) external;
}