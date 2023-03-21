// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBrewlabsIndex {
  function initialize(
    IERC20[] memory _tokens,
    IERC721 _nft,
    address _router,
    address[][] memory _paths,
    address _owner
  ) external;
}

contract BrewlabsIndexFactory is OwnableUpgradeable {
  using SafeERC20 for IERC20;

  address public implementation;
  uint256 public version;

  IERC721 public indexesNft;
  address public indexesOwner;

  address public payingToken;
  uint256 public serviceFee;
  uint256 public performanceFee;
  address public treasury;

  struct IndexesInfo {
    address indexes;
    IERC721 nft;
    IERC20[] tokens;
    address swapRouter;
    uint256 createdAt;
  }

  IndexesInfo[] public indexesList;

  event IndexesCreated(
    address indexed indexes,
    uint256 tokenCnt,
    address[] tokens,
    address nftAddr,
    address swapRouter
  );
  event SetIndexesNft(address newNftAddr);
  event SetIndexesOwner(address newOwner);
  event SetPayingInfo(address token, uint256 price);
  event SetImplementation(address impl, uint256 version);
  event SetServiceInfo(address addr, uint256 fee);

  constructor() {}

  function initialize(
    address impl,
    IERC721 nft,
    address token,
    uint256 price,
    address indexOwner,
    address adminAddr
  ) public initializer {
    __Ownable_init();

    require(token != address(0x0) && adminAddr != address(0x0), "Invalid address");

    payingToken = token;
    serviceFee = price;
    treasury = adminAddr;
    indexesOwner = indexOwner;

    indexesNft = nft;
    implementation = impl;
    version++;
    emit SetImplementation(impl, version);
  }

  function createBrewlabsIndex(
    IERC20[] memory tokens,
    address swapRouter,
    address[][] memory swapPaths
  ) external payable onlyOwner returns (address indexes) {
    require(tokens.length <= 5, "Exceed token limit");
    require(tokens.length == swapPaths.length, "Invalid config");
    require(swapRouter != address(0x0), "Invalid address");

    _transferServiceFee();

    bytes32 salt = keccak256(
      abi.encodePacked(msg.sender, tokens.length, tokens[0], block.timestamp)
    );

    indexes = Clones.cloneDeterministic(implementation, salt);
    IBrewlabsIndex(indexes).initialize(tokens, indexesNft, swapRouter, swapPaths, indexesOwner);

    indexesList.push(IndexesInfo(indexes, indexesNft, tokens, swapRouter, block.timestamp));

    address[] memory _tokens = new address[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      _tokens[i] = address(tokens[i]);
    }
    emit IndexesCreated(indexes, tokens.length, _tokens, address(indexesNft), swapRouter);

    return indexes;
  }

  function setImplementation(address impl) external onlyOwner {
    require(isContract(impl), "Not contract");
    implementation = impl;
    version++;
    emit SetImplementation(impl, version);
  }

  function setIndexesNft(IERC721 newNftAddr) external onlyOwner {
    require(address(indexesNft) == address(newNftAddr), "Same Nft address");
    indexesNft = newNftAddr;
    emit SetIndexesNft(address(newNftAddr));
  }

  function setIndexesOwner(address newOwner) external onlyOwner {
    require(address(indexesOwner) == address(newOwner), "Same owner address");
    indexesOwner = newOwner;
    emit SetIndexesOwner(newOwner);
  }

  function setServiceFee(uint256 fee) external onlyOwner {
    serviceFee = fee;
    emit SetPayingInfo(payingToken, serviceFee);
  }

  function setPayingToken(address token) external onlyOwner {
    payingToken = token;
    emit SetPayingInfo(payingToken, serviceFee);
  }

  /**
   * This method can be called by treasury.
   * @notice Update treasury wallet.
   * @param newTreasury: new treasury address
   */
  function setServiceInfo(address newTreasury, uint256 /* fee */) external {
    require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
    require(newTreasury != address(0x0), "Invalid address");

    treasury = newTreasury;
    emit SetServiceInfo(newTreasury, 0);
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
