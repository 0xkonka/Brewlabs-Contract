// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0;

interface IBrewlabsStaking {
    function initialize(
        address _stakingToken,
        address _earnedToken,
        address _dividendToken,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _uniRouter,
        address[] memory _earnedToStakedPath,
        address[] memory _reflectionToStakedPath,
        bool _hasDividend
    ) external;
}
