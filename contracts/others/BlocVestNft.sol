// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract BlocVestNft is ERC721URIStorage, Ownable {
  using SafeERC20 for IERC20;
  using Strings for uint256;

  uint256 private totalMinted;
  string private _tokenBaseURI = "";
  string[4] private rarityNames = ["Bronze", "Silver", "Gold", "Platnium"];

  bool public mintAllowed = false;
  uint256 public onetimeMintingLimit = 40;
  // address public payingToken = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
  // uint256[4] public prices = [1000 ether, 5000 ether, 35000 ether, 70000 ether];
  address public payingToken = 0x2995bD504647b5EeE414A78be1d7b24f49f00FFE; // testnet
  uint256[4] public prices = [0.01 ether, 0.05 ether, 0.35 ether, 0.7 ether];

  address public treasury = 0x0b7EaCB3EB29B13C31d934bdfe62057BB9763Bb7;
  uint256 performanceFee = 0.005 ether;

  // Optional mapping for token URIs
  mapping(uint256 => string) private _tokenURIs;
  mapping(uint256 => uint256) public rarities;
  mapping(address => uint256) public userRarities;
  mapping(address => bool) public whitelist;
  mapping(address => bool) public feeExcluded;

  event BaseURIUpdated(string uri);
  event MintEnabled();
  event MintDisabled();
  event SetPayingToken(address token);
  event SetSalePrices(uint256[4] prices);
  event SetOneTimeLimit(uint256 limit);
  event ServiceInfoUpadted(address treasury, uint256 fee);
  event WhiteListUpdated(address addr, bool enabled);
  event FeeExcluded(address addr);
  event FeeIncluded(address addr);

  constructor() ERC721("BlocVest NFT Card", "Bvest") {}

  function _transfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override {
    require(whitelist[from] || whitelist[to], "not whitelisted");
    super._transfer(from, to, tokenId);
  }

  function mint(
    address _toAddr,
    uint256 _rarity,
    uint256 _count
  ) external payable {
    require(mintAllowed, "mint was disabled");
    require(_toAddr != address(0x0), "invalid address");
    require(_rarity < 4, "invalid rarity");
    require(_count > 0, "invalid count");
    require(_count <= onetimeMintingLimit, "cannot exceed one-time limit");
    require(
      userRarities[msg.sender] == 0 || _rarity + 1 == userRarities[msg.sender],
      "can't mint other type of cards"
    );

    if (!feeExcluded[msg.sender]) {
      _transferPerformanceFee();
    }

    uint256 amount = prices[_rarity] * _count;
    IERC20(payingToken).safeTransferFrom(msg.sender, address(this), amount);

    if (userRarities[msg.sender] == 0) {
      userRarities[msg.sender] = _rarity + 1;
    }

    for (uint256 i = 0; i < _count; i++) {
      uint256 tokenId = totalMinted + 1;

      _safeMint(_toAddr, tokenId);
      _setTokenURI(tokenId, tokenId.toString());
      super._setTokenURI(tokenId, tokenId.toString());

      rarities[tokenId] = _rarity;
      totalMinted = totalMinted + 1;
    }
  }

  function setWhitelist(address _addr, bool _enabled) external onlyOwner {
    whitelist[_addr] = _enabled;
    emit WhiteListUpdated(_addr, _enabled);
  }

  function excludeFromFee(address _addr) external onlyOwner {
    feeExcluded[_addr] = true;
    emit FeeExcluded(_addr);
  }

  function includeInFee(address _addr) external onlyOwner {
    feeExcluded[_addr] = false;
    emit FeeIncluded(_addr);
  }

  function enabledMint() external onlyOwner {
    require(!mintAllowed, "already enabled");
    mintAllowed = true;
    emit MintEnabled();
  }

  function disableMint() external onlyOwner {
    require(mintAllowed, "already disabled");
    mintAllowed = false;
    emit MintDisabled();
  }

  function setPayingToken(address _token) external onlyOwner {
    require(!mintAllowed, "mint was enabled");
    require(_token != payingToken, "same token");
    require(_token != address(0x0), "invalid token");

    payingToken = _token;
    emit SetPayingToken(_token);
  }

  function setSalePrices(uint256[4] memory _prices) external onlyOwner {
    require(!mintAllowed, "mint was enabled");
    prices = _prices;
    emit SetSalePrices(_prices);
  }

  function setOneTimeMintingLimit(uint256 _limit) external onlyOwner {
    onetimeMintingLimit = _limit;
    emit SetOneTimeLimit(_limit);
  }

  function setServiceInfo(address _addr, uint256 _fee) external {
    require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
    require(_addr != address(0x0), "Invalid address");

    treasury = _addr;
    performanceFee = _fee;

    emit ServiceInfoUpadted(_addr, _fee);
  }

  function setTokenBaseURI(string memory _uri) external onlyOwner {
    _tokenBaseURI = _uri;
    emit BaseURIUpdated(_uri);
  }

  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(_exists(tokenId), "BlocVest: URI query for nonexistent token");

    string memory base = _baseURI();

    // If both are set, concatenate the baseURI (via abi.encodePacked).
    string memory metadata = string(
      abi.encodePacked(
        '{"name": "BlocVest NFT Card", "description": "BlocVest NFT Card #',
        tokenId.toString(),
        ': BlocVest NFT Cards are generated as a result of each individual.", "image": "',
        string(abi.encodePacked(base, rarityNames[rarities[tokenId]], ".mp4")),
        '", "attributes":[{"trait_type":"rarity", "value":"',
        rarityNames[rarities[tokenId]],
        '"}, {"trait_type":"number", "value":"',
        tokenId.toString(),
        '"}]}'
      )
    );

    return
      string(
        abi.encodePacked(
          "data:application/json;base64,",
          _base64(bytes(metadata))
        )
      );
  }

  function rarityOf(uint256 tokenId) external view returns (string memory) {
    return rarityNames[rarities[tokenId]];
  }

  function _transferPerformanceFee() internal {
    require(msg.value >= performanceFee, "should pay small gas to mint");

    payable(treasury).transfer(performanceFee);
    if (msg.value > performanceFee) {
      payable(msg.sender).transfer(msg.value - performanceFee);
    }
  }

  function _baseURI() internal view override returns (string memory) {
    return _tokenBaseURI;
  }

  function _setTokenURI(uint256 tokenId, string memory _tokenURI)
    internal
    override
  {
    require(_exists(tokenId), "BlocVest: URI set of nonexistent token");
    _tokenURIs[tokenId] = _tokenURI;
  }

  function _base64(bytes memory data) internal pure returns (string memory) {
    if (data.length == 0) return "";

    // load the table into memory
    string
      memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    // multiply by 4/3 rounded up
    uint256 encodedLen = 4 * ((data.length + 2) / 3);

    // add some extra buffer at the end required for the writing
    string memory result = new string(encodedLen + 32);

    assembly {
      // set the actual output length
      mstore(result, encodedLen)

      // prepare the lookup table
      let tablePtr := add(table, 1)

      // input ptr
      let dataPtr := data
      let endPtr := add(dataPtr, mload(data))

      // result ptr, jump over length
      let resultPtr := add(result, 32)

      // run over the input, 3 bytes at a time
      for {

      } lt(dataPtr, endPtr) {

      } {
        dataPtr := add(dataPtr, 3)

        // read 3 bytes
        let input := mload(dataPtr)

        // write 4 characters
        mstore(
          resultPtr,
          shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F))))
        )
        resultPtr := add(resultPtr, 1)
        mstore(
          resultPtr,
          shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F))))
        )
        resultPtr := add(resultPtr, 1)
        mstore(
          resultPtr,
          shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F))))
        )
        resultPtr := add(resultPtr, 1)
        mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
        resultPtr := add(resultPtr, 1)
      }

      // padding with '='
      switch mod(mload(data), 3)
      case 1 {
        mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
      }
      case 2 {
        mstore(sub(resultPtr, 1), shl(248, 0x3d))
      }
    }

    return result;
  }

  function rescueTokens(address _token) external onlyOwner {
    if (_token == address(0x0)) {
      uint256 _ethAmount = address(this).balance;
      payable(msg.sender).transfer(_ethAmount);
    } else {
      uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
      IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
    }
  }

  receive() external payable {}
}
