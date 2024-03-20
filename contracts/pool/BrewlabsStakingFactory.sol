// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./BrewlabsStaking.sol";
import "./IBrewlabsStaking.sol";

contract BrewlabsStakingFactory {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(BrewlabsStaking).creationCode));

    mapping(address => mapping(address => address)) public getContract;
    address[] public allContracts;

    event StakingContractCreated(
        address indexed _stakingToken,
        address indexed _earnedToken,
        address _dividendToken,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _uniRouter,
        address[] _earnedToStakedPath,
        address[] _reflectionToStakedPath,
        bool _hasDividend,
        address stakingContract,
        uint
    );

    constructor() public {}

    function createStakingContract(
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
    ) external returns (address stakingContract) {
        require(_stakingToken != address(0));
        require(_earnedToken != address(0));
        require(_dividendToken != address(0));
        require(_uniRouter != address(0));

        require(getContract[_stakingToken][_earnedToken] == address(0), "BrewLabs: Staking Contract already exists"); // single check is sufficient
        bytes memory bytecode = type(BrewlabsStaking).creationCode;
        bytes32 salt = keccak256(
            abi.encodePacked(
                _stakingToken,
                _earnedToken,
                _dividendToken,
                _rewardPerBlock,
                _depositFee,
                _withdrawFee,
                _uniRouter,
                _earnedToStakedPath,
                _reflectionToStakedPath,
                _hasDividend
            )
        );
        assembly {
            stakingContract := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IBrewlabsStaking(stakingContract).initialize(
            _stakingToken,
            _earnedToken,
            _dividendToken,
            _rewardPerBlock,
            _depositFee,
            _withdrawFee,
            _uniRouter,
            _earnedToStakedPath,
            _reflectionToStakedPath,
            _hasDividend
        );
        getContract[_stakingToken][_stakingToken] = stakingContract;
        allContracts.push(stakingContract);
        emit StakingContractCreated(
            _stakingToken,
            _earnedToken,
            _dividendToken,
            _rewardPerBlock,
            _depositFee,
            _withdrawFee,
            _uniRouter,
            _earnedToStakedPath,
            _reflectionToStakedPath,
            _hasDividend,
            stakingContract,
            allContracts.length
        );
    }
}
