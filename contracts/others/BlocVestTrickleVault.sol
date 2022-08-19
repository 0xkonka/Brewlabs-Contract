// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/IUniRouter02.sol";

interface IERC20X is IERC20 {
  function mint(address account, uint256 amount) external;
  function burn(uint256 amount) external;
}

interface IBlocVestNft is IERC721 {
  function rarities(uint256 tokenId) external view returns (uint256);
}

contract BlocVestTrickleVault is Ownable, IERC721Receiver, ReentrancyGuard {
  using SafeERC20 for IERC20;
  bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

  // IERC20 public bvst = IERC20(0xC7b29e78BcE023757928eD3839Ff92F94391842E);
  // IERC20 public bvstLP = IERC20(0xaA187EDdD4b37B8864bd5015acF07d65B79E9101);
  IERC20 public bvst = IERC20(0x8428b19C97acCD93fA10f19cbbdfF4FB71C4D175);
  IERC20 public bvstLP = IERC20(0xB37d9c39d6A3873Dca3CBfA01D795a03f41b7298);

  IERC20 public bvstX;
  uint256 public xRate = 10;
  uint256 public claimLimit = 365;
  uint256 public userLimit = 25000 ether;
  uint256 public compoundLimit = 1000;

  address public bvstNft;
  uint256 public defaultApr = 20;
  uint256[4] public cardAprs = [25, 50, 100, 150];

  struct HarvestFee {
    uint256 feeInBNB;
    uint256 feeInToken;
    uint256 fee;
  }
  HarvestFee[3] public harvestFees; // 0 - default, 1 - weekly tax, 2 - whale tax
  uint256 public depositFee = 1000;
  uint256 public whaleLimit = 85;

  struct UserInfo {
    uint256 apr;
    uint256 cardType;
    uint256 totalStaked;
    uint256 totalRewards;
    uint256 lastRewardBlock;
    uint256 lastDepositBlock;
    uint256 totalClaims;
  }
  mapping(address => UserInfo) public userInfo;
  uint256 public totalStaked;

  address public uniRouterAddress;
  address[] public tokenToBNBPath;

  uint256 public autoCompoundFeeInDay = 0.007 ether;
  mapping(address => uint256) public autoCompounds;
  address[] public autoCompounders;

  address public treasury = 0x6219B6b621E6E66a6c5a86136145E6E5bc6e4672;
  // address public treasury = 0x0b7EaCB3EB29B13C31d934bdfe62057BB9763Bb7;
  uint256 public performanceFee = 0.0015 ether;

  event Deposit(address indexed user, uint256 amount);
  event Claim(address indexed user, uint256 amount);
  event AutoCompound(address user, uint256 amount);
  event RequestAutoCompound(address user, uint256 times);

  event NftStaked(address indexed user, address nft, uint256 tokenId);

  event SetDepositFee(uint256 percent);
  event SetAutoCompoundFee(uint256 fee);
  event SetUserDepositLimit(uint256 limit);
  event SetClaimLimit(uint256 count);
  event SetDefaultApr(uint256 apr);
  event SetCardAprs(uint256[4] aprs);
  event SetHarvestFees(
    uint8 feeType,
    uint256 inBNBToTreasury,
    uint256 inTokenToTreasury,
    uint256 toContract
  );
  event SetWhaleLimit(uint256 percent);
  event SetXRate(uint256 rate);

  event AdminTokenRecovered(address tokenRecovered, uint256 amount);
  event ServiceInfoUpadted(address addr, uint256 fee);
  event SetSettings(address uniRouter, address[] tokenToBNBPath);

  constructor(
    IERC20 _tokenX,
    address _nft,
    address _uniRouter,
    address[] memory _path
  ) {
    bvstX = _tokenX;
    bvstNft = _nft;
    uniRouterAddress = _uniRouter;
    tokenToBNBPath = _path;

    harvestFees[0] = HarvestFee(0, 0, 1000);
    harvestFees[1] = HarvestFee(0, 0, 5000);
    harvestFees[2] = HarvestFee(1500, 1500, 2000);
  }

  function deposit(uint256 _amount) external payable nonReentrant {
    UserInfo storage user = userInfo[msg.sender];
    require(_amount > 0, "invalid amount");
    require(
      _amount + user.totalStaked <= userLimit,
      "cannot exceed maximum limit"
    );

    _transferPerformanceFee();

    uint256 beforeAmount = bvst.balanceOf(address(this));
    bvst.safeTransferFrom(address(msg.sender), address(this), _amount);
    uint256 afterAmount = bvst.balanceOf(address(this));
    uint256 realAmount = afterAmount - beforeAmount;
    realAmount = (realAmount * (10000 - depositFee)) / 10000;

    uint256 _pending = _claim(msg.sender);
    if (_pending == 0) {
      bvst.safeTransfer(msg.sender, _pending);
    }

    user.totalStaked = user.totalStaked + realAmount;
    user.lastRewardBlock = block.number;
    user.lastDepositBlock = block.number;
    totalStaked = totalStaked + realAmount;

    IERC20X(address(bvstX)).mint(msg.sender, realAmount * xRate);
    emit Deposit(msg.sender, realAmount);
  }

  function stakeNft(uint256 _tokenId) external payable nonReentrant {
    _transferPerformanceFee();

    uint256 _pending = _claim(msg.sender);
    if (_pending == 0) {
      bvst.safeTransfer(msg.sender, _pending);
    }

    IERC721(bvstNft).safeTransferFrom(msg.sender, address(this), _tokenId);

    UserInfo storage user = userInfo[msg.sender];
    uint256 rarity = IBlocVestNft(bvstNft).rarities(_tokenId);
    require(user.cardType < rarity + 1, "cannot stake lower level card");

    user.cardType = rarity + 1;
    user.apr = cardAprs[rarity];

    emit NftStaked(msg.sender, bvstNft, _tokenId);
  }

  function harvest() external payable nonReentrant {
    _transferPerformanceFee();

    uint256 _pending = _claim(msg.sender);
    if (_pending > 0) {
      bvst.safeTransfer(msg.sender, _pending);
    }
  }

  function compound() external payable nonReentrant {
    _transferPerformanceFee();

    uint256 _pending = _claim(msg.sender);
    UserInfo storage user = userInfo[msg.sender];

    if (_pending > 0) {
      uint256 tSupply = (bvst.totalSupply() * compoundLimit) / 10000;
      if (_pending > tSupply) _pending = tSupply;

      user.totalStaked = user.totalStaked + _pending;
      user.lastDepositBlock = block.number;
      totalStaked = totalStaked + _pending;

      IERC20X(address(bvstX)).mint(msg.sender, _pending * xRate);
      emit Deposit(msg.sender, _pending);
    }
  }

  function requestAutoCompound(uint256 _times) external payable nonReentrant {
    require(msg.value >= _times * autoCompoundFeeInDay, "insufficient compound fee");
    autoCompounds[msg.sender] = autoCompounds[msg.sender] + _times;
    autoCompounders.push(msg.sender);

    emit RequestAutoCompound(msg.sender, _times);
  }

  function autoCompound(uint256 _index) external nonReentrant {
    require(_index < autoCompounders.length, "not found");
    address _user = autoCompounders[_index];
    require(autoCompounds[_user] > 0, "cannot auto compound");

    uint256 _pending = _claim(_user);
    UserInfo storage user = userInfo[_user];

    if (_pending > 0) {
      autoCompounds[_user] = autoCompounds[_user] - 1;
      if(autoCompounds[_user] == 0) {
        autoCompounders[_index] = autoCompounders[autoCompounders.length - 1];
        autoCompounders.pop();
      }

      uint256 tSupply = (bvst.totalSupply() * compoundLimit) / 10000;
      if (_pending > tSupply) _pending = tSupply;

      user.totalStaked = user.totalStaked + _pending;
      user.lastDepositBlock = block.number;
      totalStaked = totalStaked + _pending;

      IERC20X(address(bvstX)).mint(_user, _pending * xRate);
      emit Deposit(_user, _pending);
      emit AutoCompound(_user, _pending);
    }
  }

  function pendingRewards(address _user) public view returns (uint256) {
    UserInfo memory user = userInfo[_user];

    uint256 expiryBlock = user.lastDepositBlock + 28800;
    if (user.lastDepositBlock == 0 || expiryBlock < user.lastRewardBlock) {
      return 0;
    }

    uint256 stakedAmount = user.totalStaked;
    uint256 multiplier = (
      expiryBlock > block.number ? block.number : expiryBlock
    ) - user.lastRewardBlock;

    return (multiplier * stakedAmount * user.apr) / 10000 / 28800;
  }

  function appliedTax(address _user) internal view returns (HarvestFee memory) {
    UserInfo memory user = userInfo[_user];
    if (user.lastRewardBlock == 0) {
      return harvestFees[0];
    }

    uint256 stakedAmount = bvstX.balanceOf(_user) / 10;
    uint256 tokenInLp = bvst.balanceOf(address(bvstLP));
    if (stakedAmount >= (tokenInLp * whaleLimit) / 10000) {
      return harvestFees[2];
    }

    uint256 passedBlocks = block.number - user.lastRewardBlock;
    if (passedBlocks <= 7 * 28800) return harvestFees[1];
    return harvestFees[0];
  }

  function _claim(address _user) internal returns (uint256) {
    UserInfo storage user = userInfo[_user];
    require(user.totalClaims <= claimLimit, "exceed claim limit");

    user.apr = user.cardType == 0 ? defaultApr : cardAprs[user.cardType];
    uint256 _pending = pendingRewards(_user);

    uint256 xTokenBalance = bvstX.balanceOf(_user);
    user.totalStaked = xTokenBalance / xRate;
    user.totalRewards = user.totalRewards + _pending;
    user.lastRewardBlock = block.number;
    if (_pending == 0) return 0;

    user.totalClaims = user.totalClaims + 1;

    HarvestFee memory tax = appliedTax(_user);
    uint256 feeInBNB = (_pending * tax.feeInBNB) / 10000;
    if (feeInBNB > 0) {
      _safeSwap(feeInBNB, tokenToBNBPath, treasury);
    }
    uint256 feeInToken = (_pending * tax.feeInToken) / 10000;
    uint256 fee = (_pending * tax.fee) / 10000;

    bvst.safeTransfer(treasury, feeInToken);

    emit Claim(_user, _pending);

    return _pending - feeInBNB - feeInToken - fee;
  }

  function _transferPerformanceFee() internal {
    require(
      msg.value >= performanceFee,
      "should pay small gas to compound or harvest"
    );

    payable(treasury).transfer(performanceFee);
    if (msg.value > performanceFee) {
      payable(msg.sender).transfer(msg.value - performanceFee);
    }
  }

  function setDepositFee(uint256 _percent) external onlyOwner {
    require(_percent < 10000, "invalid limit");
    depositFee = _percent;
    emit SetDepositFee(_percent);
  }

  function setAutoCompoundFee(uint256 _fee) external onlyOwner {
    autoCompoundFeeInDay = _fee;
    emit SetAutoCompoundFee(_fee);
  }

  function setDepositUserLimit(uint256 _limit) external onlyOwner {
    userLimit = _limit;
    emit SetUserDepositLimit(_limit);
  }

  function setClaimLimit(uint256 _count) external onlyOwner {
    claimLimit = _count;
    emit SetClaimLimit(_count);
  }

  function setDefaultApr(uint256 _apr) external onlyOwner {
    require(_apr < 10000, "invalid apr");
    defaultApr = _apr;
    emit SetDefaultApr(_apr);
  }

  function setCardAprs(uint256[4] memory _aprs) external onlyOwner {
    require(totalStaked > 0, "is staking");
    uint256 totalAlloc = 0;
    for (uint256 i = 0; i <= 4; i++) {
      totalAlloc = totalAlloc + _aprs[i];
      require(_aprs[i] > 0, "Invalid apr");
    }

    cardAprs = _aprs;
    emit SetCardAprs(_aprs);
  }

  function setHarvestFees(
    uint8 _feeType,
    uint256 _inBNBToTreasury,
    uint256 _inTokenToTreasury,
    uint256 _toContract
  ) external onlyOwner {
    require(_feeType <= 3, "invalid type");
    require(
      _inBNBToTreasury + _inTokenToTreasury + _toContract < 10000,
      "invalid base apr"
    );

    HarvestFee storage _fee = harvestFees[_feeType];
    _fee.feeInBNB = _inBNBToTreasury;
    _fee.feeInToken = _inTokenToTreasury;
    _fee.fee = _toContract;

    emit SetHarvestFees(
      _feeType,
      _inBNBToTreasury,
      _inTokenToTreasury,
      _toContract
    );
  }

  function setXRate(uint256 _rate) external onlyOwner {
    xRate = _rate;
    emit SetXRate(_rate);
  }

  function setWhaleLimit(uint256 _percent) external onlyOwner {
    require(_percent < 10000, "invalid limit");
    whaleLimit = _percent;
    emit SetWhaleLimit(_percent);
  }

  function setServiceInfo(address _treasury, uint256 _fee) external {
    require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
    require(_treasury != address(0x0), "Invalid address");

    treasury = _treasury;
    performanceFee = _fee;

    emit ServiceInfoUpadted(_treasury, _fee);
  }

  function setSettings(address _uniRouter, address[] memory _tokenToBNBPath)
    external
    onlyOwner
  {
    uniRouterAddress = _uniRouter;
    tokenToBNBPath = _tokenToBNBPath;
    emit SetSettings(_uniRouter, _tokenToBNBPath);
  }

  function _safeSwap(
    uint256 _amountIn,
    address[] memory _path,
    address _to
  ) internal {
    bvst.safeApprove(uniRouterAddress, _amountIn);
    IUniRouter02(uniRouterAddress)
      .swapExactTokensForETHSupportingFeeOnTransferTokens(
        _amountIn,
        0,
        _path,
        _to,
        block.timestamp + 600
      );
  }

  /**
   * @notice It allows the admin to recover wrong tokens sent to the contract
   * @param _token: the address of the token to withdraw
   * @param _amount: the number of tokens to withdraw
   * @dev This function is only callable by admin.
   */
  function rescueTokens(address _token, uint256 _amount) external onlyOwner {
    if (_token == address(0x0)) {
      payable(msg.sender).transfer(_amount);
    } else {
      IERC20(_token).safeTransfer(address(msg.sender), _amount);
    }

    emit AdminTokenRecovered(_token, _amount);
  }

  /**
   * onERC721Received(address operator, address from, uint256 tokenId, bytes data) → bytes4
   * It must return its Solidity selector to confirm the token transfer.
   * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
   */
  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external view override returns (bytes4) {
    require(msg.sender == bvstNft, "not enabled NFT");
    return _ERC721_RECEIVED;
  }

  receive() external payable {}
}
