// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBrewlabsIndexNft {
    function setMinterRole(address minter, bool status) external;
}

contract BrewlabsIndexFactory is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private constant FEE_DENOMIATOR = 10000;

    mapping(uint256 => address) public implementation;
    mapping(uint256 => uint256) public version;

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
    uint256 public feeLimit = 1000; // 10%

    struct IndexInfo {
        address index;
        uint256 category;
        uint256 version;
        address indexNft;
        address deployerNft;
        address[] tokens;
        address swapRouter;
        address deployer;
        uint256 createdAt;
    }

    IndexInfo[] private indexList;
    mapping(address => bool) public whitelist;

    /**
     * 0 - DISABLED      : Tokens are not accepted.
     * 1 - DIRECT_PATH   : Token swap possible directly to BNB.
     * 2 - LIQUID_TOKEN  : Token can be converted to BNB by burning.
     */
    mapping(address => uint8) public allowedTokens;

    event IndexCreated(
        address indexed index,
        uint256 category,
        uint256 version,
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
    event SetImplementation(uint256 category, address impl, uint256 version);
    event SetDiscountMgr(address addr);
    event TreasuryChanged(address addr);

    event SetTokenConfig(address token, uint8 flag);
    event Whitelisted(address indexed account, bool isWhitelisted);

    constructor() {}

    function initialize(
        address _impl,
        IERC721 _indexNft,
        IERC721 _deployerNft,
        address _token,
        uint256 _price,
        address _indexOwner
    ) external initializer {
        require(_impl != address(0x0), "Invalid implementation");
        require(address(_indexNft) != address(0x0), "Invalid index NFT");
        require(address(_deployerNft) != address(0x0), "Invalid deployer NFT");

        __Ownable_init();

        payingToken = _token;
        serviceFee = _price;
        treasury = _indexOwner;
        indexDefaultOwner = _indexOwner;

        indexNft = _indexNft;
        deployerNft = _deployerNft;
        implementation[0] = _impl;
        version[0] = 1;
        emit SetImplementation(0, _impl, version[0]);
    }

    function createBrewlabsIndex(address[] memory tokens, address swapRouter, address[][] memory swapPaths, uint256 fee)
        external
        payable
        returns (address index)
    {
        uint256 curCategory = 0;
        require(implementation[curCategory] != address(0x0), "Not initialized yet");

        require(tokens.length <= 5, "Exceed token limit");
        require(tokens.length == swapPaths.length, "Invalid token config");
        require(swapRouter != address(0x0), "Invalid router");
        require(fee <= feeLimit, "Cannot exeed fee limit");

        for (uint256 i = 0; i < tokens.length; i++) {
            require(isContract(address(tokens[i])), "Invalid token");
            for (uint256 j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "Cannot use same token");
            }
        }

        if (!whitelist[msg.sender]) {
            _transferServiceFee();
        }

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, tokens.length, tokens[0], block.number, block.timestamp));

        index = Clones.cloneDeterministic(implementation[curCategory], salt);
        (bool success,) = index.call(
            abi.encodeWithSignature(
                "initialize(address[],address,address,address,address[][],uint256,address,address)",
                tokens,
                address(indexNft),
                address(deployerNft),
                swapRouter,
                swapPaths,
                fee,
                indexDefaultOwner,
                msg.sender
            )
        );
        require(success, "Initialization failed");

        IBrewlabsIndexNft(address(indexNft)).setMinterRole(index, true);
        IBrewlabsIndexNft(address(deployerNft)).setMinterRole(index, true);

        indexList.push(
            IndexInfo(
                index,
                curCategory,
                version[curCategory],
                address(indexNft),
                address(deployerNft),
                tokens,
                swapRouter,
                msg.sender,
                block.timestamp
            )
        );

        emit IndexCreated(
            index,
            curCategory,
            version[curCategory],
            tokens,
            address(indexNft),
            address(deployerNft),
            swapRouter,
            msg.sender
            );
    }

    function indexCount() external view returns (uint256) {
        return indexList.length;
    }

    function getIndexInfo(uint256 idx)
        external
        view
        returns (address, uint256, address, address, address[] memory, address, address, uint256)
    {
        IndexInfo memory indexInfo = indexList[idx];
        return (
            indexInfo.index,
            indexInfo.category,
            indexInfo.indexNft,
            indexInfo.deployerNft,
            indexInfo.tokens,
            indexInfo.swapRouter,
            indexInfo.deployer,
            indexInfo.createdAt
        );
    }

    function setImplementation(uint256 category, address impl) external onlyOwner {
        require(isContract(impl), "Invalid implementation");
        implementation[category] = impl;
        version[category] = version[category] + 1;
        emit SetImplementation(category, impl, version[category]);
    }

    function setIndexNft(IERC721 newNftAddr) external onlyOwner {
        require(address(newNftAddr) != address(0x0), "Invalid NFT");
        indexNft = newNftAddr;
        emit SetIndexNft(address(newNftAddr));
    }

    function setDeployerNft(IERC721 newNftAddr) external onlyOwner {
        require(address(newNftAddr) != address(0x0), "Invalid NFT");
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

    /**
     * @notice Initialize the contract
     * @param token: staked token address
     * @param flag: staked token address
     *     0 - DISABLED      : Tokens are not accepted.
     *     1 - DIRECT_PATH   : Token swap possible directly to BNB.
     *     2 - LIQUID_TOKEN  : Token can be converted to BNB by burning.
     */
    function setAllowedToken(address token, uint8 flag) external onlyOwner {
        require(token != address(0x0), "Invalid token");
        require(flag < 2, "Invalid type");

        allowedTokens[token] = flag;
        emit SetTokenConfig(token, flag);
    }

    function setIndexFeeLimit(uint256 limit) external onlyOwner {
        require(limit <= 2000, "fee limit cannot exceed 20%");
        feeLimit = limit;
        emit SetIndexFeeLimit(feeLimit);
    }

    function setIndexOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0x0), "Invalid address");
        indexDefaultOwner = newOwner;
        emit SetIndexOwner(newOwner);
    }

    function setDiscountManager(address addr) external onlyOwner {
        require(addr == address(0x0) || isContract(addr), "Invalid discount manager");

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
