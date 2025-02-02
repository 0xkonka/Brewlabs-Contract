// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BrewlabsFarmFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(uint256 => address) public implementation;
    mapping(uint256 => uint256) public version;

    address public farmDefaultOwner;

    address public payingToken;
    uint256 public serviceFee;
    address public treasury;

    struct FarmInfo {
        address farm;
        uint256 category;
        uint256 version;
        address lpToken;
        address rewardToken;
        address dividendToken;
        bool hasDividend;
        address deployer;
        uint256 createdAt;
    }

    FarmInfo[] public farmInfo;
    mapping(address => bool) public whitelist;
    address public feeManager;

    event FarmCreated(
        address indexed farm,
        uint256 category,
        uint256 version,
        address lpToken,
        address rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend,
        address deployer
    );
    event DualFarmCreated(
        address indexed farm,
        uint256 category,
        uint256 version,
        address lpToken,
        address[2] rewardTokens,
        uint256[2] rewardsPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        address deployer
    );
    event SetFarmOwner(address newOwner);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(uint256 category, address impl, uint256 version);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    constructor() {}

    function reinitialize() external reinitializer(2) {
        version[1] = 1;
        feeManager = 0x9dF9d5A7597cd4BF781d4FA9b98077376F6643AD;
    }

    function initialize(
        address impl,
        address token,
        uint256 price,
        address farmOwner
    ) external initializer {
        require(impl != address(0x0), "Invalid implementation");

        __Ownable_init();

        payingToken = token;
        serviceFee = price;
        treasury = farmOwner;
        farmDefaultOwner = farmOwner;

        implementation[0] = impl;
        version[0] = 1;
        emit SetImplementation(0, impl, 1);
    }

    function createBrewlabsDualFarm(
        address lpToken,
        address[2] memory rewardTokens,
        uint256[2] memory rewardsPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        uint256 duration
    ) external payable returns (address farm) {
        uint256 category = 1;

        require(
            implementation[category] != address(0x0),
            "Not initialized yet"
        );

        require(isContract(lpToken), "Invalid LP token");
        require(
            isContract(rewardTokens[0]) && isContract(rewardTokens[1]),
            "Invalid reward token"
        );
        require(depositFee <= 2000, "Invalid deposit fee");
        require(withdrawFee <= 2000, "Invalid withdraw fee");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt = keccak256(
            abi.encodePacked(
                msg.sender,
                lpToken,
                rewardTokens,
                rewardsPerBlock,
                depositFee,
                withdrawFee,
                duration,
                block.number,
                block.timestamp
            )
        );

        farm = Clones.cloneDeterministic(implementation[category], salt);
        (bool success, ) = farm.call(
            abi.encodeWithSignature(
                "initialize(address,address[2],uint256[2],uint256,uint256,uint256,address,address,address)",
                lpToken,
                rewardTokens,
                rewardsPerBlock,
                depositFee,
                withdrawFee,
                duration,
                farmDefaultOwner,
                feeManager,
                msg.sender
            )
        );
        require(success, "Initialization failed");

        farmInfo.push(
            FarmInfo(
                farm,
                category,
                version[category],
                lpToken,
                rewardTokens[0],
                rewardTokens[1],
                false,
                msg.sender,
                block.timestamp
            )
        );

        emit DualFarmCreated(
            farm,
            category,
            version[category],
            lpToken,
            rewardTokens,
            rewardsPerBlock,
            depositFee,
            withdrawFee,
            msg.sender
        );
    }

    function createBrewlabsFarm(
        address lpToken,
        address rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        uint256 duration,
        bool hasDividend
    ) external payable returns (address farm) {
        uint256 category = 0;

        require(
            implementation[category] != address(0x0),
            "Not initialized yet"
        );

        require(isContract(lpToken), "Invalid LP token");
        require(isContract(rewardToken), "Invalid reward token");
        require(depositFee <= 2000, "Invalid deposit fee");
        require(withdrawFee <= 2000, "Invalid withdraw fee");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt = keccak256(
            abi.encodePacked(
                msg.sender,
                lpToken,
                rewardToken,
                duration,
                block.number,
                block.timestamp
            )
        );

        farm = Clones.cloneDeterministic(implementation[category], salt);
        (bool success, ) = farm.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,uint256,uint256,uint256,bool,address,address)",
                lpToken,
                rewardToken,
                dividendToken,
                rewardPerBlock,
                depositFee,
                withdrawFee,
                duration,
                hasDividend,
                farmDefaultOwner,
                msg.sender
            )
        );
        require(success, "Initialization failed");

        farmInfo.push(
            FarmInfo(
                farm,
                category,
                version[category],
                lpToken,
                rewardToken,
                dividendToken,
                hasDividend,
                msg.sender,
                block.timestamp
            )
        );

        emit FarmCreated(
            farm,
            category,
            version[category],
            lpToken,
            rewardToken,
            dividendToken,
            rewardPerBlock,
            depositFee,
            withdrawFee,
            hasDividend,
            msg.sender
        );
    }

    function farmCount() external view returns (uint256) {
        return farmInfo.length;
    }

    function setImplementation(
        uint256 category,
        address impl
    ) external onlyOwner {
        require(isContract(impl), "Invalid implementation");
        implementation[category] = impl;
        version[category] = version[category] + 1;
        emit SetImplementation(category, impl, version[category]);
    }

    function setFarmOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0x0), "Invalid address");
        farmDefaultOwner = newOwner;
        emit SetFarmOwner(newOwner);
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
            IERC20(payingToken).safeTransferFrom(
                msg.sender,
                treasury,
                serviceFee
            );
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
