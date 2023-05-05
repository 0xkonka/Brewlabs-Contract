// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBrewlabsFarm {
    function initialize(
        IERC20 _lpToken,
        IERC20 _earnedToken,
        address _dividendToken,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        bool _hasDividend,
        address _owner,
        address _deployer
    ) external;
}

contract BrewlabsFarmFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public implementation;
    uint256 public version;

    address public farmDefaultOwner;

    address public payingToken;
    uint256 public serviceFee;
    uint256 public performanceFee;
    address public treasury;

    struct FarmInfo {
        address farm;
        uint256 version;
        address lpToken;
        address rewardToken;
        address dividendToken;
        bool hasDividend;
        address deployer;
        uint256 createdAt;
    }

    FarmInfo[] public farmList;
    mapping(address => bool) public whitelist;

    event FarmCreated(
        address indexed farm,
        address lpToken,
        address rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend,
        address deployer
    );
    event SetFarmOwner(address newOwner);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(address impl, uint256 version);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    constructor() {}

    function initialize(address impl, address token, uint256 price, address farmOwner) external initializer {
        require(impl != address(0x0), "Invalid implementation");

        __Ownable_init();

        payingToken = token;
        serviceFee = price;
        treasury = farmOwner;
        farmDefaultOwner = farmOwner;

        implementation = impl;
        version++;
        emit SetImplementation(impl, version);
    }

    function createBrewlabsFarm(
        IERC20 lpToken,
        IERC20 rewardToken,
        address dividendToken,
        uint256 rewardPerBlock,
        uint256 depositFee,
        uint256 withdrawFee,
        bool hasDividend
    ) external payable returns (address farm) {
        require(implementation != address(0x0), "Not initialized yet");

        require(address(lpToken) != address(0x0), "Invalid LP token");
        require(address(rewardToken) != address(0x0), "Invalid reward token");
        require(depositFee <= 2000, "Invalid deposit fee");
        require(withdrawFee <= 2000, "Invalid withdraw fee");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, address(lpToken), address(rewardToken), block.timestamp));

        farm = Clones.cloneDeterministic(implementation, salt);
        IBrewlabsFarm(farm).initialize(
            lpToken,
            rewardToken,
            dividendToken,
            rewardPerBlock,
            depositFee,
            withdrawFee,
            hasDividend,
            farmDefaultOwner,
            msg.sender
        );

        farmList.push(
            FarmInfo(
                farm,
                version,
                address(lpToken),
                address(rewardToken),
                dividendToken,
                hasDividend,
                msg.sender,
                block.timestamp
            )
        );

        emit FarmCreated(
            farm,
            address(lpToken),
            address(rewardToken),
            dividendToken,
            rewardPerBlock,
            depositFee,
            withdrawFee,
            hasDividend,
            msg.sender
            );

        return farm;
    }

    function farmCount() external view returns (uint256) {
        return farmList.length;
    }

    function setImplementation(address impl) external onlyOwner {
        require(isContract(impl), "Invalid implementation");
        implementation = impl;
        version++;
        emit SetImplementation(impl, version);
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
