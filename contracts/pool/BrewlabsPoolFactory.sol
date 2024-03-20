// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BrewlabsPoolFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint public constant MAX_FEE_AMOUNT = 1 ether;

    mapping(uint256 => address) public implementation;
    mapping(uint256 => uint256) public version;

    address public poolDefaultOwner;

    address public payingToken;
    uint256 public serviceFee;
    address public treasury;
    address public swapAggregator;

    struct PoolInfo {
        address pool;
        uint256 category; // 0 - core, 1 - lockup, 2 - lockup penalty
        uint256 version;
        address stakingToken;
        address rewardToken;
        address dividendToken;
        uint256 lockup;
        bool hasDividend;
        address deployer;
        uint256 createdAt;
    }

    PoolInfo[] public poolInfo;
    mapping(address => bool) public whitelist;

    event SinglePoolCreated(
        address indexed pool,
        uint256 version,
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
        uint256 version,
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
        uint256 version,
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
    event SetSwapAggregator(address addr);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    constructor() {}

    function initialize(address token, uint256 price, address poolOwner) external initializer {
        require(token != address(0x0), "Invalid address");
        require(poolOwner != address(0x0), "Invalid address");

        __Ownable_init();

        swapAggregator = 0x260C865B96C6e70A25228635F8123C3A7ab0b4e2;

        payingToken = token;
        serviceFee = price;
        treasury = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;
        poolDefaultOwner = poolOwner;
    }

    function createBrewlabsSinglePool(
        address stakingToken,
        address rewardToken,
        address dividendToken,
        uint256 duration,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend
    ) external payable returns (address pool) {
        require(implementation[0] != address(0x0), "No implementation");
        require(isContract(stakingToken), "Invalid staking token");
        require(isContract(rewardToken), "Invalid reward token");
        require(depositFee < 2000, "Invalid deposit fee");
        require(withdrawFee < 2000, "Invalid withdraw fee");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }
        {
            bytes32 salt =
                keccak256(abi.encodePacked(msg.sender, "0", stakingToken, rewardToken, hasDividend, block.timestamp));

            pool = Clones.cloneDeterministic(implementation[0], salt);
            (bool success,) = pool.call(
                abi.encodeWithSignature(
                    "initialize(address,address,address,uint256,uint256,uint256,uint256,bool,address,address,address)",
                    stakingToken,
                    rewardToken,
                    dividendToken,
                    duration,
                    rewardPerBlock,
                    depositFee,
                    withdrawFee,
                    hasDividend,
                    swapAggregator,
                    poolDefaultOwner,
                    msg.sender
                )
            );
            require(success, "Initialization failed");
        }
        poolInfo.push(
            PoolInfo(
                pool,
                0,
                version[0],
                stakingToken,
                rewardToken,
                dividendToken,
                0,
                hasDividend,
                msg.sender,
                block.timestamp
            )
        );

        emit SinglePoolCreated(
            pool,
            version[0],
            stakingToken,
            rewardToken,
            dividendToken,
            rewardPerBlock,
            depositFee,
            withdrawFee,
            hasDividend,
            msg.sender
        );
    }

    function createBrewlabsLockupPools(
        address stakingToken,
        address rewardToken,
        address dividendToken,
        uint256 duration,
        uint256[] memory lockDurations,
        uint256[] memory rewardsPerBlock,
        uint256[] memory depositFees,
        uint256[] memory withdrawFees
    ) external payable returns (address pool) {
        require(implementation[1] != address(0x0), "No implementation");
        require(isContract(stakingToken), "Invalid staking token");
        require(isContract(rewardToken), "Invalid reward token");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }
        {
            bytes32 salt = keccak256(abi.encodePacked(msg.sender, "1", stakingToken, rewardToken, block.timestamp));

            pool = Clones.cloneDeterministic(implementation[1], salt);
            (bool success,) = pool.call(
                abi.encodeWithSignature(
                    "initialize(address,address,address,uint256,address,address,address)",
                    stakingToken,
                    rewardToken,
                    dividendToken,
                    duration,
                    swapAggregator,
                    poolDefaultOwner,
                    msg.sender
                )
            );
            require(success, "Initialization failed");
        }
        for (uint256 i = 0; i < lockDurations.length; i++) {
            require(depositFees[i] < 2000, "Invalid deposit fee");
            require(withdrawFees[i] < 2000, "Invalid withdraw fee");
            {
                (bool success,) = pool.call(
                    abi.encodeWithSignature(
                        "addLockup(uint256,uint256,uint256,uint256,uint256)",
                        lockDurations[i],
                        depositFees[i],
                        withdrawFees[i],
                        rewardsPerBlock[i],
                        0
                    )
                );
                require(success, "Adding lockup failed");
            }
            poolInfo.push(
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
                version[1],
                address(stakingToken),
                address(rewardToken),
                dividendToken,
                i,
                lockDurations[i],
                rewardsPerBlock[i],
                depositFees[i],
                withdrawFees[i],
                msg.sender
            );
        }
    }

    function createBrewlabsLockupPoolsWithPenalty(
        address stakingToken,
        address rewardToken,
        address dividendToken,
        uint256 duration,
        uint256[] memory lockDurations,
        uint256[] memory rewardsPerBlock,
        uint256[] memory depositFees,
        uint256[] memory withdrawFees,
        uint256 penaltyFee
    ) external payable returns (address pool) {
        require(implementation[2] != address(0x0), "No implementation");
        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        {
            bytes32 salt =
                keccak256(abi.encodePacked(msg.sender, "2", stakingToken, rewardToken, block.number, block.timestamp));

            pool = Clones.cloneDeterministic(implementation[2], salt);
            (bool success,) = pool.call(
                abi.encodeWithSignature(
                    "initialize(address,address,address,uint256,uint256,address,address,address)",
                    stakingToken,
                    rewardToken,
                    dividendToken,
                    duration,
                    penaltyFee,
                    swapAggregator,
                    poolDefaultOwner,
                    msg.sender
                )
            );
            require(success, "Initialization failed");
        }

        for (uint256 i = 0; i < lockDurations.length; i++) {
            require(depositFees[i] < 2000, "Invalid deposit fee");
            require(withdrawFees[i] < 2000, "Invalid withdraw fee");
            {
                (bool success,) = pool.call(
                    abi.encodeWithSignature(
                        "addLockup(uint256,uint256,uint256,uint256,uint256)",
                        lockDurations[i],
                        depositFees[i],
                        withdrawFees[i],
                        rewardsPerBlock[i],
                        0
                    )
                );
                require(success, "Adding lockup failed");
            }

            poolInfo.push(
                PoolInfo(
                    pool, 2, version[2], stakingToken, rewardToken, dividendToken, i, true, msg.sender, block.timestamp
                )
            );

            emit LockupPenaltyPoolCreated(
                pool,
                version[2],
                stakingToken,
                rewardToken,
                dividendToken,
                i,
                lockDurations[i],
                rewardsPerBlock[i],
                depositFees[i],
                withdrawFees[i],
                msg.sender
            );
        }
    }

    function poolCount() external view returns (uint256) {
        return poolInfo.length;
    }

    function setImplementation(uint256 category, address impl) external onlyOwner {
        require(isContract(impl), "Not contract");
        implementation[category] = impl;
        version[category]++;
        emit SetImplementation(category, impl, version[category]);
    }

    function setSwapAggregator(address _aggregator) external onlyOwner {
        require(_aggregator != address(0x0), "Invalid address");

        swapAggregator = _aggregator;
        emit SetSwapAggregator(_aggregator);
    }

    function setPoolOwner(address newOwner) external onlyOwner {
        require(address(poolDefaultOwner) != address(newOwner), "Same owner address");
        poolDefaultOwner = newOwner;
        emit SetPoolOwner(newOwner);
    }

    function setServiceFee(uint256 fee) external onlyOwner {
        require( fee <= MAX_FEE_AMOUNT, "Fee mustn't exceed the maximum");

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
            // payable(msg.sender).transfer(_ethAmount);
            (bool success, ) = msg.sender.call{value: _ethAmount}("");
            require(success, "Unable to send value, recipient may have reverted");
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    function _transferServiceFee() internal {
        uint256 actualFee;
        if (payingToken == address(0x0)) {
            require(msg.value >= serviceFee, "Not enough fee");
            actualFee = serviceFee;
            (bool success, ) = treasury.call{value: serviceFee}("");
            require(success, "Unable to send value, recipient may have reverted");
            // payable(treasury).transfer(serviceFee);
        } else {
            IERC20(payingToken).safeTransferFrom(msg.sender, treasury, serviceFee);
            actualFee = IERC20(payingToken).balanceOf(address(this));
            require(actualFee >= serviceFee, "Insufficient tokens received");
        }

        // Refund excess payment to the caller
        if (payingToken == address(0x0)) {
            uint256 excess = msg.value - actualFee;
            if (excess > 0) {
                // payable(msg.sender).transfer(excess);
                (bool success, ) = msg.sender.call{value: excess}("");
                require(success, "Unable to send value, recipient may have reverted");
            }
        } else {
            uint256 excess = IERC20(payingToken).balanceOf(address(this)) - actualFee;
            if (excess > 0) {
                IERC20(payingToken).safeTransfer(msg.sender, excess);
            }
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
