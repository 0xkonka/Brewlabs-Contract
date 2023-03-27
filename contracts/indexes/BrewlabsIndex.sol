// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "../libs/IUniRouter02.sol";
import "../libs/AggregatorV3Interface.sol";

interface IBrewlabsIndexNft is IERC721 {
    function mint(address to) external returns (uint256);
    function burn(uint256 tokenId) external;
}

// BrewlabsIndex is index contracts that offer a range of token collections to buy as "Brewlabs Index"
// most likely top 100 tokens that do not require tax slippage.
// Ideally the index tokens will buy 2-4 tokens (they will mostly be pegged tokens of the top 100 tokens that we will choose).
//
// Note User may select an index that will contain PEGGED-ETH + BTCB,
// the will determine how much (by a sliding scale) BNB they will allocate to each token.
// For example 1 BNB buy:
//    User chooses 30%; 0.30 BNB to buy PEGGED-ETH (BEP20)
//    User chooses 70%, 0.70BNB to buy BTCB.
contract BrewlabsIndex is Ownable, ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    uint256 private PERCENTAGE_PRECISION;
    address private PRICE_FEED;

    IERC721 public nft;
    IERC20[] public tokens;
    uint256 public NUM_TOKENS;

    address public swapRouter;
    address[][] public ethToTokenPaths;

    // Info of each user.
    struct UserInfo {
        uint256[] amounts; // How many tokens that user has bought
        uint256 zappedEthAmount; // ETH amount that user sold
    }

    mapping(address => UserInfo) private users;

    struct NftInfo {
        uint256 level;
        uint256[] amounts; // locked token amounts in NFT
        uint256 zappedEthAmount; // ETH amount that sold for above tokens
    }

    mapping(uint256 => NftInfo) private nfts;
    uint256[] public totalStaked;

    uint256 public fee;
    uint256 public performanceFee;
    address public treasury;
    address public feeWallet;

    event TokenZappedIn(address indexed user, uint256 ethAmount, uint256[] percents, uint256[] amountOuts);
    event TokenZappedOut(address indexed user, uint256 ethAmount, uint256[] amounts);
    event TokenClaimed(address indexed user, uint256[] amounts);
    event TokenLocked(address indexed user, uint256[] amounts, uint256 ethAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[] amounts, uint256 ethAmount, uint256 tokenId);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetFee(uint256 fee);
    event SetFeeWallet(address addr);
    event SetSettings(address router, address[][] paths);

    modifier onlyInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize index contract.
     * @param _tokens: token list that user can buy in a transaction
     * @param _nft: NFT contract address for locking tokens
     * @param _router: swap router address
     * @param _paths: swap paths for each token
     */
    function initialize(
        IERC20[] memory _tokens,
        IERC721 _nft,
        address _router,
        address[][] memory _paths,
        address _owner
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");

        isInitialized = true;

        // initialize default variables
        PERCENTAGE_PRECISION = 10000;
        PRICE_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; // BNB-USD FEED
        NUM_TOKENS = _tokens.length;

        fee = 25;
        performanceFee = 0.01 ether;
        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        feeWallet = _owner;

        nft = _nft;
        tokens = _tokens;
        swapRouter = _router;
        ethToTokenPaths = _paths;
        totalStaked = new uint256[](NUM_TOKENS);

        _transferOwnership(_owner);
    }

    /**
     * @notice Buy tokens by paying ETH and lock tokens in contract.
     *         When buy tokens, should pay performance fee and processing fee.
     * @param _percents: list of ETH allocation points to buy tokens
     */
    function zapIn(uint256[] memory _percents) external payable onlyInitialized nonReentrant {
        uint256 totalPercentage = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalPercentage += _percents[i];
        }
        require(totalPercentage <= PERCENTAGE_PRECISION, "Total percentage cannot exceed 10000");

        uint256 ethAmount = msg.value;

        // pay processing fee
        uint256 buyingFee = (ethAmount * fee) / PERCENTAGE_PRECISION;
        payable(feeWallet).transfer(buyingFee);
        ethAmount -= buyingFee;

        UserInfo storage user = users[msg.sender];

        // buy tokens
        uint256 amount;
        uint256[] memory amountOuts = new uint256[](NUM_TOKENS);
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountIn = (ethAmount * _percents[i]) / PERCENTAGE_PRECISION;
            if (amountIn == 0) continue;

            amountOuts[i] = _safeSwapEth(amountIn, getSwapPath(i, true), address(this));

            if (user.amounts.length == 0) {
                user.amounts = new uint256[](NUM_TOKENS);
            }
            user.amounts[i] += amountOuts[i];
            amount += amountIn;

            totalStaked[i] += amountOuts[i];
        }
        user.zappedEthAmount += amount;
        emit TokenZappedIn(msg.sender, amount, _percents, amountOuts);

        if(totalPercentage < PERCENTAGE_PRECISION) {
            payable(msg.sender).transfer(ethAmount * (PERCENTAGE_PRECISION - totalPercentage) / PERCENTAGE_PRECISION);
        }
    }

    /**
     * @notice Claim tokens from contract.
     *         If the user exits the index in a loss then there is no fee.
     *         If the user exists the index in a profit, processing fee will be applied.
     */
    function claimTokens() external onlyInitialized nonReentrant {
        UserInfo memory user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        uint256 expectedAmt = _expectedEth(user.amounts);
        if (expectedAmt > user.zappedEthAmount) {
            for (uint8 i = 0; i < NUM_TOKENS; i++) {
                uint256 claimFee = (user.amounts[i] * fee) / PERCENTAGE_PRECISION;
                tokens[i].safeTransfer(feeWallet, claimFee);
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
    function zapOut() external onlyInitialized nonReentrant {
        UserInfo memory user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        uint256 ethAmount;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalStaked[i] -= user.amounts[i];
            uint256 amountOut = _safeSwapForETH(user.amounts[i], getSwapPath(i, false));
            ethAmount += amountOut;
        }

        if (ethAmount > user.zappedEthAmount) {
            uint256 swapFee = (ethAmount * fee) / PERCENTAGE_PRECISION;
            payable(feeWallet).transfer(swapFee);

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
    function mintNft() external payable onlyInitialized nonReentrant returns (uint256) {
        UserInfo storage user = users[msg.sender];
        require(user.zappedEthAmount > 0, "No available tokens");

        _transferPerformanceFee();

        // mint NFT
        uint256 tokenId = IBrewlabsIndexNft(address(nft)).mint(msg.sender);

        // lock available tokens for NFT
        NftInfo storage nftData = nfts[tokenId];
        nftData.amounts = user.amounts;
        nftData.zappedEthAmount = user.zappedEthAmount;

        uint256 price = _getPriceFromChainlink();
        uint256 usdAmount = nftData.zappedEthAmount * price / 10 ** 18;
        nftData.level = 1;
        if (usdAmount < 1000) nftData.level = 0;
        if (usdAmount > 5000) nftData.level = 2;

        delete users[msg.sender];
        emit TokenLocked(msg.sender, nftData.amounts, nftData.zappedEthAmount, tokenId);

        return tokenId;
    }

    /**
     * @notice Stake the NFT back into the index to claim/zap out their tokens.
     */
    function stakeNft(uint256 tokenId) external payable onlyInitialized nonReentrant {
        UserInfo storage user = users[msg.sender];

        _transferPerformanceFee();

        // burn NFT
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        IBrewlabsIndexNft(address(nft)).burn(tokenId);

        NftInfo memory nftData = nfts[tokenId];
        if (user.amounts.length == 0) user.amounts = new uint256[](NUM_TOKENS);
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
        if (ethAmount == 0) return (amounts, ethAmount);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            amounts[i] = _userData.amounts[i];
        }
    }

    /**
     * @notice Returns tokens locked in NFT and ETH amount at the time when bought tokens.
     * @param _tokenId: owned tokenId
     */
    function nftInfo(uint256 _tokenId)
        external
        view
        returns (uint256 level, uint256[] memory amounts, uint256 ethAmount)
    {
        NftInfo memory _nftData = nfts[_tokenId];
        level = _nftData.level;
        ethAmount = _nftData.zappedEthAmount;
        amounts = new uint256[](NUM_TOKENS);
        if (ethAmount == 0) return (1, amounts, ethAmount);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            amounts[i] = _nftData.amounts[i];
        }
    }

    /**
     * @notice Returns estimated eth amount when user zapout.
     * @param _user: user address
     */
    function estimateEthforUser(address _user) external view returns (uint256) {
        return _expectedEth(users[_user].amounts);
    }

    /**
     * @notice Returns estimated eth amount that can get from NFT item.
     * @param _tokenId: token Id of BrewlabsIndex NFT
     */
    function estimateEthforNft(uint256 _tokenId) external view returns (uint256) {
        return _expectedEth(nfts[_tokenId].amounts);
    }

    /**
     * @notice Returns swap path for token specified by index.
     * @param _index: token index
     * @param _isZapIn: swap direction(true: ETH to token, false: token to ETH)
     */
    function getSwapPath(uint8 _index, bool _isZapIn) public view returns (address[] memory) {
        if (_isZapIn) return ethToTokenPaths[_index];

        uint256 len = ethToTokenPaths[_index].length;
        address[] memory _path = new address[](len);
        for (uint8 j = 0; j < len; j++) {
            _path[j] = ethToTokenPaths[_index][len - j - 1];
        }

        return _path;
    }

    /**
     * @notice Update swap router and paths for each token.
     * @param _router: swap router address
     * @param _paths: list of swap path for each tokens
     */
    function setSwapSettings(address _router, address[][] memory _paths) external onlyOwner onlyInitialized {
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
     * @notice Update processing fee wallet.
     * @param _addr: wallet address
     */
    function setFeeWallet(address _addr) external onlyOwner {
        require(_addr != address(0x0), "Invalid address");
        feeWallet = _addr;
        emit SetFeeWallet(_addr);
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
    function _expectedEth(uint256[] memory amounts) internal view returns (uint256 amountOut) {
        amountOut = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            if (amounts[i] == 0) continue;
            uint256[] memory _amounts = IUniRouter02(swapRouter).getAmountsOut(amounts[i], getSwapPath(i, false));
            amountOut += _amounts[_amounts.length - 1];
        }
    }

    function _getPriceFromChainlink() internal view returns (uint256) {
        if (PRICE_FEED == address(0x0)) return 0;

        (, int256 answer,,,) = AggregatorV3Interface(PRICE_FEED).latestRoundData();
        // It's fine for price to be 0. We have two price feeds.
        if (answer == 0) {
            return 0;
        }

        // Extend the decimals to 1e18.
        uint256 retVal = uint256(answer);
        uint256 price = retVal * (10 ** (18 - uint256(AggregatorV3Interface(PRICE_FEED).decimals())));

        return price;
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
