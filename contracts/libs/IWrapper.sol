// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IWrapper {
    function deposit() external payable returns (uint256);
    function withdraw(uint256) external returns (uint256);
}
