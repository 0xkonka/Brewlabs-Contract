// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./libs/IUniRouter02.sol";

interface IBrewlabsIndexesNft is IERC721 {
    function mint(address to) external returns (uint256);
    function burn(uint256 tokenId) external;
}

// BrewlabsIndexes is index contracts that offer a range of token collections to buy as "Brewlabs Indexes"
// most likely top 100 tokens that do not require tax slippage.
// Ideally the index tokens will buy 2-4 tokens (they will mostly be pegged tokens of the top 100 tokens that we will choose).
//
// Note User may select an index that will contain PEGGED-ETH + BTCB,
// the will determine how much (by a sliding scale) BNB they will allocate to each token.
// For example 1 BNB buy:
//    User chooses 30%; 0.30 BNB to buy PEGGED-ETH (BEP20)
//    User chooses 70%, 0.70BNB to buy BTCB.
contract BrewlabsIndexes is Ownable, ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool public isInitialized;
    uint256 private constant PERCENTAGE_PRECISION = 10000;
    uint8 public constant NUM_TOKENS = 2;

    IERC721 public nft;
    IERC20[NUM_TOKENS] public tokens;

    address public swapRouter;
    address[][NUM_TOKENS] public ethToTokenPaths;

    // Info of each user.
    struct UserInfo {
        uint256[NUM_TOKENS] amounts; // How many tokens that user has bought
        uint256 zappedEthAmount; // ETH amount that user sold
    }

    mapping(address => UserInfo) private users;

    struct NftInfo {
        uint256[NUM_TOKENS] amounts; // locked token amounts in NFT
        uint256 zappedEthAmount; // ETH amount that sold for above tokens
    }

    mapping(uint256 => NftInfo) private nfts;
    uint256[NUM_TOKENS] public totalStaked;

    uint256 public fee = 25;
    address public treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
    uint256 public performanceFee = 0.0035 ether;

    event TokenZappedIn(
        address indexed user, uint256 ethAmount, uint256[NUM_TOKENS] percents, uint256[NUM_TOKENS] amountOuts
    );
    event TokenZappedOut(address indexed user, uint256 ethAmount, uint256[NUM_TOKENS] amounts);
    event TokenClaimed(address indexed user, uint256[NUM_TOKENS] amounts);
    event TokenLocked(address indexed user, uint256[NUM_TOKENS] amounts, uint256 ethAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[NUM_TOKENS] amounts, uint256 ethAmount, uint256 tokenId);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetFee(uint256 fee);
    event SetSettings(address router, address[][NUM_TOKENS] paths);

    modifier onlyInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize indexes contract.
     * @param _tokens: token list that user can buy in a transaction
     * @param _nft: NFT contract address for locking tokens
     * @param _router: swap router address
     * @param _paths: swap paths for each token
     */
    function initialize(
        IERC20[NUM_TOKENS] memory _tokens,
        IERC721 _nft,
        address _router,
        address[][NUM_TOKENS] memory _paths
    ) external onlyOwner {
        require(!isInitialized, "Already initialized");

        isInitialized = true;

        nft = _nft;
        tokens = _tokens;
        swapRouter = _router;
        ethToTokenPaths = _paths;
    }

    /**
     * @notice Buy tokens by paying ETH and lock tokens in contract.
     *         When buy tokens, should pay performance fee and processing fee.
     * @param _percents: list of ETH allocation points to buy tokens
     */
    function buyTokens(uint256[NUM_TOKENS] memory _percents) external payable onlyInitialized nonReentrant {
        _transferPerformanceFee();

        uint256 totalPercentage = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalPercentage += _percents[i];
        }
        require(totalPercentage <= PERCENTAGE_PRECISION, "Total percentage cannot exceed 10000");

        uint256 ethAmount = msg.value - performanceFee;

        // pay processing fee
        uint256 buyingFee = (ethAmount * fee) / PERCENTAGE_PRECISION;
        payable(treasury).transfer(buyingFee);
        ethAmount -= buyingFee;

        UserInfo storage user = users[msg.sender];

        // buy tokens
        uint256 amount;
        uint256[NUM_TOKENS] memory amountOuts;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountIn = (ethAmount * _percents[i]) / PERCENTAGE_PRECISION;
            if (amountIn == 0) continue;

            amountOuts[i] = _safeSwapEth(amountIn, getSwapPath(0, i), address(this));

            user.amounts[i] += amountOuts[i];
            amount += amountIn;

            totalStaked[i] += amountOuts[i];
        }
        user.zappedEthAmount += amount;

        emit TokenZappedIn(msg.sender, amount, _percents, amountOuts);
    }

    /**
     * @notice Claim tokens from contract.
     *         If the user exits the index in a loss then there is no fee.
     *         If the user exists the index in a profit, processing fee will be applied.
     */
    function claimTokens() external payable onlyInitialized nonReentrant {
        UserInfo memory user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        uint256 expectedAmt = _expectedEth(user.amounts);
        if (expectedAmt > user.zappedEthAmount) {
            for (uint8 i = 0; i < NUM_TOKENS; i++) {
                uint256 claimFee = (user.amounts[i] * fee) / PERCENTAGE_PRECISION;
                tokens[i].safeTransfer(treasury, claimFee);
                tokens[i].safeTransfer(msg.sender, user.amounts[i] - claimFee);
            }
        } else {
            for (uint8 i = 0; i < NUM_TOKENS; i++) {
                totalStaked[i] -= user.amounts[i];
                tokens[i].safeTransfer(msg.sender, user.amounts[i]);
            }
        }

        emit TokenClaimed(msg.sender, user.amounts);
        delete users[msg.sender];
    }

    /**
     * @notice Sale tokens from contract and claim ETH.
     *         If the user exits the index in a loss then there is no fee.
     *         If the user exists the index in a profit, processing fee will be applied.
     */
    function saleTokens() external payable onlyInitialized nonReentrant {
        UserInfo memory user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        uint256 ethAmount;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalStaked[i] -= user.amounts[i];
            uint256 amountOut = _safeSwapForETH(user.amounts[i], getSwapPath(1, i));
            ethAmount += amountOut;
        }

        if (ethAmount > user.zappedEthAmount) {
            uint256 swapFee = (ethAmount * fee) / PERCENTAGE_PRECISION;
            payable(treasury).transfer(swapFee);

            ethAmount -= swapFee;
        }

        payable(msg.sender).transfer(ethAmount);
        emit TokenZappedOut(msg.sender, ethAmount, user.amounts);
        delete users[msg.sender];
    }

    /**
     * @notice Once the user purchases the tokens through the contract, the user can then choose to at anytime
     *  to mint an NFT that would represent the ownership of their tokens in the contract.
     * The purpose of this is to allow users to mint an NFT that represents their value in the index and at their discretion,
     *  transfer or sell that NFT to another wallet.
     */
    function lockTokens() external payable onlyInitialized nonReentrant returns (uint256) {
        UserInfo storage user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        // mint NFT
        uint256 tokenId = IBrewlabsIndexesNft(address(nft)).mint(msg.sender);

        // lock available tokens for NFT
        NftInfo storage nftData = nfts[tokenId];
        nftData.amounts = user.amounts;
        nftData.zappedEthAmount = user.zappedEthAmount;

        delete users[msg.sender];
        emit TokenLocked(msg.sender, nftData.amounts, nftData.zappedEthAmount, tokenId);

        return tokenId;
    }

    /**
     * @notice Stake the NFT back into the index to claim/zap out their tokens.
     */
    function unlockTokens(uint256 tokenId) external payable onlyInitialized nonReentrant {
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

    /**
     * @notice Returns purchased tokens and ETH amount at the time when bought tokens.
     * @param _user: user address
     */
    function userInfo(address _user) external view returns (uint256[] memory amounts, uint256 ethAmount) {
        UserInfo memory _userData = users[_user];
        ethAmount = _userData.zappedEthAmount;
        amounts = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            amounts[i] = _userData.amounts[i];
        }
    }

    /**
     * @notice Returns tokens locked in NFT and ETH amount at the time when bought tokens.
     * @param _tokenId: owned tokenId
     */
    function nftInfo(uint256 _tokenId) external view returns (uint256[] memory amounts, uint256 ethAmount) {
        NftInfo memory _nftData = nfts[_tokenId];
        ethAmount = _nftData.zappedEthAmount;
        amounts = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            amounts[i] = _nftData.amounts[i];
        }
    }

    /**
     * @notice Returns swap path for token specified by index.
     * @param _type: swap direction(0: ETH to token, 1: token to ETH)
     * @param _index: token index
     */
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

    /**
     * @notice Update swap router and paths for each token.
     * @param _router: swap router address
     * @param _paths: list of swap path for each tokens
     */
    function setSwapSettings(address _router, address[][NUM_TOKENS] memory _paths) external onlyOwner onlyInitialized {
        require(_router != address(0x0), "Invalid address");
        require(IUniRouter02(_router).WETH() != address(0x0), "Invalid swap router");

        swapRouter = _router;
        ethToTokenPaths = _paths;
        emit SetSettings(_router, _paths);
    }

    /**
     * @notice Update processing fee.
     * @param _fee: percentage in point
     */
    function setFee(uint256 _fee) external onlyOwner {
        require(_fee <= PERCENTAGE_PRECISION, "Invalid percentage");
        fee = _fee;
        emit SetFee(_fee);
    }

    /**
     * This method can be called by treasury.
     * @notice Update treasury wallet and performance fee.
     * @param _addr: new treasury address
     * @param _fee: percentage in point
     */
    function setServiceInfo(address _addr, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_addr != address(0x0), "Invalid address");

        treasury = _addr;
        performanceFee = _fee;

        emit ServiceInfoUpadted(_addr, _fee);
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

    /**
     * @notice Process performance fee.
     */
    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "Should pay small gas to call method");
        payable(treasury).transfer(performanceFee);
    }

    /**
     * @notice Returns the expected eth amount by swapping provided tokens.
     * @param amounts: amounts to swap
     */
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
