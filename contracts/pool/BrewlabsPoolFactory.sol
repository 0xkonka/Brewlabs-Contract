// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBrewlabsStaking {
    function initialize(
        IERC20 _stakingToken,
        IERC20 _earnedToken,
        address _dividendToken,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _uniRouter,
        address[] memory _earnedToStakedPath,
        address[] memory _reflectionToStakedPath,
        bool _hasDividend,
        address _owner,
        address _operator
    ) external;
}

interface IBrewlabsLockup {
    function initialize(
        IERC20 _stakingToken,
        IERC20 _earnedToken,
        address _dividendToken,
        address _uniRouter,
        address[] memory _earnedToStakedPath,
        address[] memory _reflectionToStakedPath,
        address _owner,
        address _operator
    ) external;
    function addLockup(
        uint256 duration,
        uint256 depositFee,
        uint256 withdrawFee,
        uint256 rate,
        uint256 totalStakedLimit
    ) external;
}

interface IBrewlabsLockupPenalty {
    function initialize(
        IERC20 _stakingToken,
        IERC20 _earnedToken,
        address _dividendToken,
        address _uniRouter,
        address[] memory _earnedToStakedPath,
        address[] memory _reflectionToStakedPath,
        uint256 _penaltyFee,
        address _owner,
        address _operator
    ) external;
}

contract BrewlabsPoolFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address[3] public implementation;
    uint256[3] public version;

    address public poolDefaultOwner;

    address public payingToken;
    uint256 public serviceFee;
    uint256 public performanceFee;
    address public treasury;

    struct PoolInfo {
        address pool;
        uint256 poolCategory; // 0 - core, 1 - lockup, 2 - lockup penalty
        uint256 version;
        address stakingToken;
        address rewardToken;
        address dividendToken;
        uint256 lockup;
        bool hasDividend;
        address deployer;
        uint256 createdAt;
    }

    PoolInfo[] public poolList;
    mapping(address => bool) public whitelist;

    event SinglePoolCreated(
        address indexed pool,
        address stakingToken,
        address rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend,
        address deployer
    );

    event LockupPoolCreated(
        address indexed pool,
        address stakingToken,
        address rewardToken,
        address dividendToken,
        uint256 lockup,
        uint256 lockDuration,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        address deployer
    );

    event LockupPenaltyPoolCreated(
        address indexed pool,
        address stakingToken,
        address rewardToken,
        address dividendToken,
        uint256 lockup,
        uint256 lockDuration,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        address deployer
    );

    event SetPoolOwner(address newOwner);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(uint256 category, address impl, uint256 version);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    constructor() {}

    function initialize(address token, uint256 price, address poolOwner) external initializer {
        __Ownable_init();

        require(token != address(0x0), "Invalid address");

        payingToken = token;
        serviceFee = price;
        treasury = poolOwner;
        poolDefaultOwner = poolOwner;
    }

    function createBrewlabsSinglePool(
        IERC20 stakingToken,
        IERC20 rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        address uniRouter,
        address[] memory earnedToStakedPath,
        address[] memory reflectionToStakedPath,
        bool hasDividend
    ) external payable returns (address pool) {
        require(implementation[0] != address(0x0), "No implementation");
        require(depositFee < 2000, "Invalid deposit fee");
        require(withdrawFee < 2000, "Invalid withdraw fee");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt = keccak256(
            abi.encodePacked(msg.sender, "0", address(stakingToken), address(rewardToken), hasDividend, block.timestamp)
        );

        pool = Clones.cloneDeterministic(implementation[0], salt);
        IBrewlabsStaking(pool).initialize(
            stakingToken,
            rewardToken,
            dividendToken,
            rewardPerBlock,
            depositFee,
            withdrawFee,
            uniRouter,
            earnedToStakedPath,
            reflectionToStakedPath,
            hasDividend,
            poolDefaultOwner,
            msg.sender
        );

        poolList.push(
            PoolInfo(
                pool,
                0,
                version[0],
                address(stakingToken),
                address(rewardToken),
                dividendToken,
                0,
                hasDividend,
                msg.sender,
                block.timestamp
            )
        );

        emit SinglePoolCreated(
            pool,
            address(stakingToken),
            address(rewardToken),
            dividendToken,
            rewardPerBlock,
            depositFee,
            withdrawFee,
            hasDividend,
            msg.sender
            );

        return pool;
    }

    function createBrewlabsLockupPools(
        IERC20 stakingToken,
        IERC20 rewardToken,
        address dividendToken,
        address uniRouter,
        address[] memory earnedToStakedPath,
        address[] memory reflectionToStakedPath,
        uint256[] memory durations,
        uint256[] memory rewardsPerBlock,
        uint256[] memory depositFees,
        uint256[] memory withdrawFees
    ) external payable returns (address pool) {
        require(implementation[1] != address(0x0), "No implementation");
        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt =
            keccak256(abi.encodePacked(msg.sender, "1", address(stakingToken), address(rewardToken), block.timestamp));

        pool = Clones.cloneDeterministic(implementation[1], salt);
        IBrewlabsLockup(pool).initialize(
            stakingToken,
            rewardToken,
            dividendToken,
            uniRouter,
            earnedToStakedPath,
            reflectionToStakedPath,
            poolDefaultOwner,
            msg.sender
        );

        for (uint256 i = 0; i < durations.length; i++) {
            require(depositFees[i] < 2000, "Invalid deposit fee");
            require(withdrawFees[i] < 2000, "Invalid withdraw fee");

            IBrewlabsLockup(pool).addLockup(durations[i], depositFees[i], withdrawFees[i], rewardsPerBlock[i], 0);

            poolList.push(
                PoolInfo(
                    pool,
                    1,
                    version[1],
                    address(stakingToken),
                    address(rewardToken),
                    dividendToken,
                    i,
                    true,
                    msg.sender,
                    block.timestamp
                )
            );

            emit LockupPoolCreated(
                pool,
                address(stakingToken),
                address(rewardToken),
                dividendToken,
                i,
                durations[i],
                rewardsPerBlock[i],
                depositFees[i],
                withdrawFees[i],
                msg.sender
                );
        }

        return pool;
    }

    function createBrewlabsLockupPoolsWithPenalty(
        IERC20 stakingToken,
        IERC20 rewardToken,
        address dividendToken,
        address uniRouter,
        address[] memory earnedToStakedPath,
        address[] memory reflectionToStakedPath,
        uint256[] memory durations,
        uint256[] memory rewardsPerBlock,
        uint256[] memory depositFees,
        uint256[] memory withdrawFees
    ) external payable returns (address pool) {
        require(implementation[2] != address(0x0), "No implementation");
        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt =
            keccak256(abi.encodePacked(msg.sender, "2", address(stakingToken), address(rewardToken), block.timestamp));

        pool = Clones.cloneDeterministic(implementation[2], salt);
        IBrewlabsLockupPenalty(pool).initialize(
            stakingToken,
            rewardToken,
            dividendToken,
            uniRouter,
            earnedToStakedPath,
            reflectionToStakedPath,
            500,
            poolDefaultOwner,
            msg.sender
        );

        for (uint256 i = 0; i < durations.length; i++) {
            require(depositFees[i] < 2000, "Invalid deposit fee");
            require(withdrawFees[i] < 2000, "Invalid withdraw fee");

            IBrewlabsLockup(pool).addLockup(durations[i], depositFees[i], withdrawFees[i], rewardsPerBlock[i], 0);

            poolList.push(
                PoolInfo(
                    pool,
                    2,
                    version[2],
                    address(stakingToken),
                    address(rewardToken),
                    dividendToken,
                    i,
                    true,
                    msg.sender,
                    block.timestamp
                )
            );

            emit LockupPenaltyPoolCreated(
                pool,
                address(stakingToken),
                address(rewardToken),
                dividendToken,
                i,
                durations[i],
                rewardsPerBlock[i],
                depositFees[i],
                withdrawFees[i],
                msg.sender
                );
        }

        return pool;
    }

    function poolCount() external view returns (uint256) {
        return poolList.length;
    }

    function setImplementation(uint256 category, address impl) external onlyOwner {
        require(isContract(impl), "Not contract");
        implementation[category] = impl;
        version[category]++;
        emit SetImplementation(category, impl, version[category]);
    }

    function setPoolOwner(address newOwner) external onlyOwner {
        require(address(poolDefaultOwner) != address(newOwner), "Same owner address");
        poolDefaultOwner = newOwner;
        emit SetPoolOwner(newOwner);
    }

    function setServiceFee(uint256 fee) external onlyOwner {
        serviceFee = fee;
        emit SetPayingInfo(payingToken, serviceFee);
    }

    function setPayingToken(address token) external onlyOwner {
        payingToken = token;
        emit SetPayingInfo(payingToken, serviceFee);
    }

    function addToWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = true;
        emit Whitelisted(_addr, true);
    }

    function removeFromWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = false;
        emit Whitelisted(_addr, false);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0x0), "Invalid address");

        treasury = newTreasury;
        emit TreasuryChanged(newTreasury);
    }

    /**
     * @notice Emergency withdraw tokens.
     * @param _token: token address
     */
    function rescueTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            uint256 _ethAmount = address(this).balance;
            payable(msg.sender).transfer(_ethAmount);
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    function _transferServiceFee() internal {
        if (payingToken == address(0x0)) {
            require(msg.value >= serviceFee, "Not enough fee");
            payable(treasury).transfer(serviceFee);
        } else {
            IERC20(payingToken).safeTransferFrom(msg.sender, treasury, serviceFee);
        }
    }

    // check if address is contract
    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    receive() external payable {}
}
