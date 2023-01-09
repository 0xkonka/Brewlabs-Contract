// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./libs/IUniRouter02.sol";

interface IBrewlabsIndexesNft is IERC721 {
    function mint() external returns (uint256);
    function burn(uint256 tokenId) external;
}

contract BrewlabsIndexes is Ownable, ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool public isInitialized;
    uint256 private constant PERCENTAGE_PRECISION = 10000;
    uint8 public constant NUM_TOKENS = 2;

    IERC721 public nft;
    IERC20[NUM_TOKENS] public tokens;

    address public swapRouter;
    address[NUM_TOKENS][] public ethToTokenPaths;

    struct UserInfo {
        uint256[NUM_TOKENS] amounts;
        uint256 zappedEthAmount;
    }

    mapping(address => UserInfo) private users;

    struct NftInfo {
        uint256[NUM_TOKENS] amounts;
        uint256 zappedEthAmount;
    }

    mapping(uint256 => NftInfo) private nfts;

    uint256 public fee = 25;
    address public treasury = 0x408c4aDa67aE1244dfeC7D609dea3c232843189A;
    uint256 public performanceFee = 0.0035 ether;

    event TokenZappedIn(
        address indexed user, uint256 ethAmount, uint256[NUM_TOKENS] percents, uint256[NUM_TOKENS] amountOuts
    );
    event TokenZappedOut(address indexed user, uint256 ethAmount);
    event TokenClaimed(address indexed user, uint256[NUM_TOKENS] amounts);
    event TokenLocked(address indexed user, uint256[NUM_TOKENS] amounts, uint256 ethAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[NUM_TOKENS] amounts, uint256 ethAmount, uint256 tokenId);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetFee(uint256 fee);
    event SetSettings(address router, address[NUM_TOKENS][] paths);

    modifier onlyInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    constructor() {}

    function initialize(
        IERC20[NUM_TOKENS] memory _tokens,
        IERC721 _nft,
        address _router,
        address[NUM_TOKENS][] memory _paths
    ) external onlyOwner {
        require(!isInitialized, "Already initialized");

        isInitialized = true;

        nft = _nft;
        tokens = _tokens;
        swapRouter = _router;
        ethToTokenPaths = _paths;
    }

    function buyTokens(uint256[NUM_TOKENS] memory _percents) external payable onlyInitialized {
        _transferPerformanceFee();

        uint256 totalPercentage = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalPercentage += _percents[i];
        }
        require(totalPercentage <= PERCENTAGE_PRECISION, "Total percentage cannot exceed 10000");

        uint256 ethAmount = msg.value - performanceFee;

        // pay processing fee
        uint256 buyingFee = ethAmount * fee / PERCENTAGE_PRECISION;
        payable(treasury).transfer(buyingFee);
        ethAmount -= buyingFee;

        UserInfo storage user = users[msg.sender];

        // buy tokens
        uint256 amount;
        uint256[NUM_TOKENS] memory amountOuts;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountIn = ethAmount * _percents[i] / PERCENTAGE_PRECISION;
            if (amountIn == 0) continue;

            amountOuts[i] = _safeSwapEth(amountIn, getSwapPath(0, i), address(this));

            user.amounts[i] += amountOuts[i];
            amount += amountIn;
        }
        user.zappedEthAmount += amount;

        emit TokenZappedIn(msg.sender, amount, _percents, amountOuts);
    }

    function claimTokens() external payable onlyInitialized {
        UserInfo memory user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        uint256 expectedAmt = _expectedEth(user.amounts);
        if (expectedAmt > user.zappedEthAmount) {
            for (uint8 i = 0; i < NUM_TOKENS; i++) {
                uint256 claimFee = user.amounts[i] * fee / PERCENTAGE_PRECISION;
                tokens[i].safeTransfer(treasury, claimFee);
                tokens[i].safeTransfer(msg.sender, user.amounts[i] - claimFee);
            }
        } else {
            for (uint8 i = 0; i < NUM_TOKENS; i++) {
                tokens[i].safeTransfer(msg.sender, user.amounts[i]);
            }
        }

        emit TokenClaimed(msg.sender, user.amounts);
        delete users[msg.sender];
    }

    function saleTokens() external payable onlyInitialized {
        UserInfo memory user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        uint256 ethAmount;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountOut = _safeSwapForETH(user.amounts[i], getSwapPath(1, i));
            ethAmount += amountOut;
        }

        if (ethAmount > user.zappedEthAmount) {
            uint256 swapFee = ethAmount * fee / PERCENTAGE_PRECISION;
            payable(treasury).transfer(swapFee);

            ethAmount -= swapFee;
        }
        delete users[msg.sender];

        payable(msg.sender).transfer(ethAmount);
        emit TokenZappedOut(msg.sender, ethAmount);
    }

    function lockTokens() external payable onlyInitialized {
        UserInfo storage user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        // mint NFT
        uint256 tokenId = IBrewlabsIndexesNft(address(nft)).mint();

        // lock available tokens for NFT
        NftInfo storage nftData = nfts[tokenId];
        nftData.amounts = user.amounts;
        nftData.zappedEthAmount = user.zappedEthAmount;

        delete users[msg.sender];
        emit TokenLocked(msg.sender, nftData.amounts, nftData.zappedEthAmount, tokenId);
    }

    function unlockTokens(uint256 tokenId) external payable onlyInitialized {
        UserInfo storage user = users[msg.sender];

        _transferPerformanceFee();

        // burn NFT
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        IBrewlabsIndexesNft(address(nft)).burn(tokenId);

        NftInfo memory nftData = nfts[tokenId];
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            user.amounts[i] += nftData.amounts[i];
        }
        user.zappedEthAmount = nftData.zappedEthAmount;

        emit TokenUnLocked(msg.sender, nftData.amounts, nftData.zappedEthAmount, tokenId);
        delete nfts[tokenId];
    }

    function userInfo(address _user) external view returns (UserInfo memory) {
        return users[_user];
    }

    function nftInfo(uint256 _tokenId) external view returns (NftInfo memory) {
        return nfts[_tokenId];
    }

    function getSwapPath(uint8 _type, uint8 _index) public view returns (address[] memory) {
        uint256 len = ethToTokenPaths[_index].length;
        address[] memory _path = new address[](len);
        for (uint8 j = 0; j < len; j++) {
            if (_type == 0) {
                _path[j] = ethToTokenPaths[_index][j];
            } else {
                _path[j] = ethToTokenPaths[_index][len - j - 1];
            }
        }

        return _path;
    }

    function setSwapSettings(address _router, address[NUM_TOKENS][] memory _paths) external onlyOwner onlyInitialized {
        require(_router != address(0x0), "Invalid address");
        require(IUniRouter02(_router).WETH() != address(0x0), "Invalid swap router");

        swapRouter = _router;
        ethToTokenPaths = _paths;
        emit SetSettings(_router, _paths);
    }

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee <= PERCENTAGE_PRECISION, "Invalid percentage");
        fee = _fee;
        emit SetFee(_fee);
    }

    function setServiceInfo(address _addr, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_addr != address(0x0), "Invalid address");

        treasury = _addr;
        performanceFee = _fee;

        emit ServiceInfoUpadted(_addr, _fee);
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

    function _transferPerformanceFee() internal {
        require(msg.value > performanceFee, "Should pay small gas to call method");
        payable(treasury).transfer(performanceFee);
    }

    function _expectedEth(uint256[NUM_TOKENS] memory amounts) internal view returns (uint256 amountOut) {
        amountOut = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            if (amounts[i] == 0) continue;
            uint256[] memory _amounts = IUniRouter02(swapRouter).getAmountsOut(amounts[i], getSwapPath(1, i));
            amountOut += _amounts[_amounts.length - 1];
        }
    }

    /**
     * @notice get token from ETH via swap.
     * @param _amountIn: eth amount to swap
     * @param _path: swap path
     * @param _to: receiver address
     */
    function _safeSwapEth(uint256 _amountIn, address[] memory _path, address _to) internal returns (uint256) {
        address _token = _path[_path.length - 1];
        uint256 beforeAmt = IERC20(_token).balanceOf(address(this));
        IUniRouter02(swapRouter).swapExactETHForTokensSupportingFeeOnTransferTokens{value: _amountIn}(
            0, _path, _to, block.timestamp + 600
        );
        uint256 afterAmt = IERC20(_token).balanceOf(address(this));

        return afterAmt - beforeAmt;
    }

    /**
     * @notice swap tokens to ETH.
     * @param _amountIn: token amount to swap
     * @param _path: swap path
     */
    function _safeSwapForETH(uint256 _amountIn, address[] memory _path) internal returns (uint256) {
        IERC20(_path[0]).safeApprove(swapRouter, _amountIn);

        uint256 beforeAmt = address(this).balance;
        IUniRouter02(swapRouter).swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amountIn, 0, _path, address(this), block.timestamp + 600
        );

        return address(this).balance - beforeAmt;
    }

    receive() external payable {}
}
