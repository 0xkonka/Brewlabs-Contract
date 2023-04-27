// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBrewlabsIndex {
    function initialize(
        IERC20[] memory _tokens,
        IERC721 _indexNft,
        IERC721 _deployerNft,
        address _router,
        address[][] memory _paths,
        uint256 _fee,
        address _owner,
        address _deployer
    ) external;
}

interface IBrewlabsIndexNft {
    function setMinterRole(address minter, bool status) external;
}

contract BrewlabsIndexFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private constant FEE_DENOMIATOR = 10000;

    address public implementation;
    uint256 public version;

    IERC721 public indexNft;
    IERC721 public deployerNft;
    address public indexDefaultOwner;

    address public payingToken;
    uint256 public serviceFee;
    uint256 public performanceFee;
    address public treasury;

    address public discountMgr;
    address public brewlabsWallet = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;
    uint256 public brewlabsFee = 25; // 0.25%
    uint256 public feeLimit = 500; // 5%

    struct IndexInfo {
        address index;
        uint256 version;
        IERC721 indexNft;
        IERC721 deployerNft;
        IERC20[] tokens;
        address swapRouter;
        address deployer;
        uint256 createdAt;
    }

    IndexInfo[] public indexList;
    mapping(address => bool) public whitelist;

    event IndexCreated(
        address indexed index,
        address[] tokens,
        address indexNft,
        address deployerNft,
        address swapRouter,
        address deployer
    );
    event SetIndexNft(address newNftAddr);
    event SetDeployerNft(address newOwner);
    event SetIndexOwner(address newOwner);
    event SetBrewlabsFee(uint256 fee);
    event SetBrewlabsWallet(address wallet);
    event SetIndexFeeLimit(uint256 limit);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(address impl, uint256 version);
    event SetDiscountMgr(address addr);
    event TreasuryChanged(address addr);
    event Whitelisted(address indexed account, bool isWhitelisted);

    constructor() {}

    function initialize(address impl, IERC721 nft, IERC721 dNft, address token, uint256 price, address indexOwner)
        external
        initializer
    {
        __Ownable_init();

        require(token != address(0x0), "Invalid address");

        payingToken = token;
        serviceFee = price;
        treasury = indexOwner;
        indexDefaultOwner = indexOwner;

        indexNft = nft;
        deployerNft = dNft;
        implementation = impl;
        version++;
        emit SetImplementation(impl, version);
    }

    function createBrewlabsIndex(IERC20[] memory tokens, address swapRouter, address[][] memory swapPaths, uint256 fee)
        external
        payable
        returns (address index)
    {
        require(tokens.length <= 5, "Exceed token limit");
        require(tokens.length == swapPaths.length, "Invalid config");
        require(swapRouter != address(0x0), "Invalid address");
        require(fee <= feeLimit, "Cannot exeed fee limit");

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, tokens.length, tokens[0], block.timestamp));

        index = Clones.cloneDeterministic(implementation, salt);
        IBrewlabsIndex(index).initialize(
            tokens, indexNft, deployerNft, swapRouter, swapPaths, fee, indexDefaultOwner, msg.sender
        );
        IBrewlabsIndexNft(address(indexNft)).setMinterRole(index, true);
        IBrewlabsIndexNft(address(deployerNft)).setMinterRole(index, true);

        indexList.push(
            IndexInfo(index, version, indexNft, deployerNft, tokens, swapRouter, msg.sender, block.timestamp)
        );

        address[] memory _tokens = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens[i] = address(tokens[i]);
        }
        emit IndexCreated(index, _tokens, address(indexNft), address(deployerNft), swapRouter, msg.sender);

        return index;
    }

    function indexCount() external view returns (uint256) {
        return indexList.length;
    }

    function getIndexInfo(uint256 idx)
        external
        view
        returns (address, IERC721, IERC721, IERC20[] memory, address, address, uint256)
    {
        IndexInfo memory indexInfo = indexList[idx];
        return (
            indexInfo.index,
            indexInfo.indexNft,
            indexInfo.deployerNft,
            indexInfo.tokens,
            indexInfo.swapRouter,
            indexInfo.deployer,
            indexInfo.createdAt
        );
    }

    function setImplementation(address impl) external onlyOwner {
        require(isContract(impl), "Not contract");
        implementation = impl;
        version++;
        emit SetImplementation(impl, version);
    }

    function setIndexNft(IERC721 newNftAddr) external onlyOwner {
        require(address(indexNft) != address(newNftAddr), "Same Nft address");
        indexNft = newNftAddr;
        emit SetIndexNft(address(newNftAddr));
    }

    function setDeployerNft(IERC721 newNftAddr) external onlyOwner {
        require(address(deployerNft) != address(newNftAddr), "Same Nft address");
        deployerNft = newNftAddr;
        emit SetDeployerNft(address(newNftAddr));
    }

    function setBrewlabsWallet(address wallet) external onlyOwner {
        require(wallet != address(0x0), "Invalid wallet");
        brewlabsWallet = wallet;
        emit SetBrewlabsWallet(wallet);
    }

    function setBrewlabsFee(uint256 fee) external onlyOwner {
        require(fee <= feeLimit, "fee cannot exceed limit");
        brewlabsFee = fee;
        emit SetBrewlabsFee(brewlabsFee);
    }

    function setIndexFeeLimit(uint256 limit) external onlyOwner {
        require(limit <= 2000, "fee limit cannot exceed 20%");
        feeLimit = limit;
        emit SetIndexFeeLimit(feeLimit);
    }

    function setIndexOwner(address newOwner) external onlyOwner {
        require(address(indexDefaultOwner) != address(newOwner), "Same owner address");
        indexDefaultOwner = newOwner;
        emit SetIndexOwner(newOwner);
    }

    function setDiscountManager(address addr) external onlyOwner {
        discountMgr = addr;
        emit SetDiscountMgr(addr);
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
