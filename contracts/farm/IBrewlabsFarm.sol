// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBrewlabsFarm {
    function initialize(
        IERC20 _lpToken,
        IERC20 _rewardToken,
        address _dividendToken,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _duration,
        bool _hasDividend,
        address _owner,
        address _deployer
    ) external;

    function lpToken() external view returns (address);
    function rewardToken() external view returns (address);
    function dividendToken() external view returns (address);
    function hasDividend() external view returns (bool);
    function autoAdjustableForRewardRate() external view returns (bool);

    function duration() external view returns (uint256);
    function startBlock() external view returns (uint256);
    function bonusEndBlock() external view returns (uint256);
    function rewardPerBlock() external view returns (uint256);
    function lastRewardBlock() external view returns (uint256);
    function accTokenPerShare() external view returns (uint256);
    function accDividendPerShare() external view returns (uint256);
    function depositFee() external view returns (uint256);
    function withdrawFee() external view returns (uint256);

    function feeAddress() external view returns (address);
    function treasury() external view returns (address);
    function performanceFee() external view returns (uint256);
    function rewardFee() external view returns (uint256);

    function factory() external view returns (address);
    function deployer() external view returns (address);
    function operator() external view returns (address);
    function owner() external view returns (address);

    function userInfo() external view returns (uint256 amount, uint256 rewardDebt, uint256 reflectionDebt);
    function totalStaked() external view returns (uint256);
    function paidRewards() external view returns (uint256);

    function swapSettings()
        external
        view
        returns (
            address swapRouter,
            address[] memory earnedToToken0,
            address[] memory earnedToToken1,
            address[] memory reflectionToToken0,
            address[] memory reflectionToToken1,
            bool enabled
        );

    function deposit(uint256 _amount) external payable;
    function withdraw(uint256 _amount) external payable;
    function claimReward() external payable;
    function claimDividend() external payable;
    function compoundReward() external payable;
    function compoundDividend() external payable;
    function emergencyWithdraw() external;

    function availableRewardTokens() external view returns (uint256);
    function availableDividendTokens() external view returns (uint256);
    function insufficientRewards() external view returns (uint256);
    function pendingRewards(address _user) external view returns (uint256);
    function pendingReflections(address _user) external view returns (uint256);

    function transferToHarvest() external;
    function depositRewards(uint256 _amount) external;
    function increaseEmissionRate(uint256 _amount) external;
    function emergencyRewardWithdraw(uint256 _amount) external;
    function emergencyWithdrawReflections() external;
    function rescueTokens(address _token) external;

    function startReward() external;
    function stopReward() external;
    function updateEndBlock(uint256 _endBlock) external;
    function updateEmissionRate(uint256 _rewardPerBlock) external;
    function setServiceInfo(address _treasury, uint256 _fee) external;

    function setDuration(uint256 _duration) external;
    function setAutoAdjustableForRewardRate(bool _status) external;
    function transferOperator(address _operator) external;
    function setSettings(uint256 _depositFee, uint256 _withdrawFee, address _feeAddr) external;
    function setSwapSetting(
        address _uniRouter,
        address[] memory _earnedToToken0,
        address[] memory _earnedToToken1,
        address[] memory _reflectionToToken0,
        address[] memory _reflectionToToken1,
        bool _enabled
    ) external;
}
