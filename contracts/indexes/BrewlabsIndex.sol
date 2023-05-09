// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "../libs/AggregatorV3Interface.sol";
import "../libs/IUniRouter02.sol";
import "../libs/IWETH.sol";

interface IBrewlabsIndexFactory {
    function brewlabsFee() external view returns (uint256);
    function feeLimit() external view returns (uint256);
    function brewlabsWallet() external view returns (address);
    function discountMgr() external view returns (address);
    function allowedTokens(address token) external view returns (uint8);
}

interface IBrewlabsIndexNft {
    function mint(address to) external returns (uint256);
    function burn(uint256 tokenId) external;
}

interface IBrewlabsDiscountMgr {
    function discountOf(address user) external view returns (uint256);
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

    uint256 private FEE_DENOMINATOR;
    address private PRICE_FEED;
    address public WBNB;

    address public factory;
    IERC721 public indexNft;
    IERC721 public deployerNft;
    IERC20[] public tokens;
    uint256 public NUM_TOKENS;

    address public swapRouter;
    address[][] public ethToTokenPaths;

    // Info of each user.
    struct UserInfo {
        uint256[] amounts; // How many tokens that user has bought
        uint256 usdAmount; // ETH amount that user sold
    }

    mapping(address => UserInfo) private users;

    struct NftInfo {
        uint256 level;
        uint256[] amounts; // locked token amounts in NFT
        uint256 usdAmount; // ETH amount that sold for above tokens
    }

    mapping(uint256 => NftInfo) private nfts;
    uint256[] public totalStaked;

    uint256 public fee;
    uint256 public performanceFee;
    address public treasury;
    address public deployer;
    address public commissionWallet;

    uint256 public totalCommissions;
    uint256[] private pendingCommissions;

    bool private deployerNftMintable;
    uint256 public deployerNftId;

    event TokenZappedIn(
        address indexed user,
        uint256 ethAmount,
        uint256[] percents,
        uint256[] amountOuts,
        uint256 usdAmount,
        uint256 commission
    );
    event TokenZappedOut(address indexed user, uint256[] amounts, uint256 ethAmount, uint256 commission);
    event TokenClaimed(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 commission);
    event TokenLocked(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 tokenId);

    event DeployerNftMinted(address indexed user, address nft, uint256 tokenId);
    event DeployerNftStaked(address indexed user, uint256 tokenId);
    event DeployerNftUnstaked(address indexed user, uint256 tokenId);
    event PendingCommissionClaimed(address indexed user);

    event ServiceInfoChanged(address addr, uint256 fee);
    event SetDeployerFee(uint256 fee);
    event SetSettings(address router, address[][] paths);

    modifier onlyInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize index contract.
     * @param _tokens: token list that user can buy in a transaction
     * @param _indexNft: Index NFT address
     * @param _deployerNft: Deployer NFT address
     * @param _router: swap router address
     * @param _paths: swap paths for each token
     * @param _fee: additional fee for deployer
     * @param _owner: index owner address
     * @param _deployer: index deployer address
     */
    function initialize(
        IERC20[] memory _tokens,
        IERC721 _indexNft,
        IERC721 _deployerNft,
        address _router,
        address[][] memory _paths,
        uint256 _fee,
        address _owner,
        address _deployer
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");
        require(_tokens.length == _paths.length, "Mismatch between number of swap paths and number of tokens");

        isInitialized = true;

        // initialize default variables
        FEE_DENOMINATOR = 10000;
        PRICE_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; // BNB-USD FEED
        WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        NUM_TOKENS = _tokens.length;

        fee = _fee;
        performanceFee = 0.01 ether;
        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        deployer = _deployer;
        commissionWallet = _deployer;

        factory = msg.sender;

        indexNft = _indexNft;
        deployerNft = _deployerNft;
        tokens = _tokens;
        swapRouter = _router;
        ethToTokenPaths = _paths;
        totalStaked = new uint256[](NUM_TOKENS);

        pendingCommissions = new uint256[](NUM_TOKENS + 1);
        deployerNftMintable = true;

        _transferOwnership(_owner);
    }

    /**
     * @notice Buy tokens by paying ETH and lock tokens in contract.
     *         When buy tokens, should pay processing fee(brewlabs fixed fee + deployer fee).
     * @param _percents: list of ETH allocation points to buy tokens
     */
    function zapIn(address _token, uint256 _amount, uint256[] memory _percents)
        external
        payable
        onlyInitialized
        nonReentrant
    {
        uint256 totalPercentage = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalPercentage += _percents[i];
        }
        require(totalPercentage <= FEE_DENOMINATOR, "Total percentage cannot exceed 10000");

        uint256 ethAmount = _beforeZapIn(_token, _amount);

        // pay brewlabs fee
        uint256 discount = _getDiscount(msg.sender);
        uint256 brewsFee = (ethAmount * IBrewlabsIndexFactory(factory).brewlabsFee() * discount) / FEE_DENOMINATOR ** 2;
        payable(IBrewlabsIndexFactory(factory).brewlabsWallet()).transfer(brewsFee);
        // pay deployer fee
        uint256 deployerFee = (ethAmount * fee * discount) / FEE_DENOMINATOR ** 2;
        payable(deployer).transfer(deployerFee);

        UserInfo storage user = users[msg.sender];
        ethAmount -= brewsFee + deployerFee;

        // buy tokens
        uint256 amount;
        uint256[] memory amountOuts = new uint256[](NUM_TOKENS);
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountIn = (ethAmount * _percents[i]) / FEE_DENOMINATOR;
            if (amountIn == 0) continue;

            if (address(tokens[i]) == WBNB) {
                IWETH(WBNB).deposit{value: amountIn}();
                amountOuts[i] = amountIn;
            } else {
                amountOuts[i] = _safeSwapEth(amountIn, getSwapPath(i, true), address(this));
            }

            if (user.amounts.length == 0) {
                user.amounts = new uint256[](NUM_TOKENS);
            }
            user.amounts[i] += amountOuts[i];
            amount += amountIn;

            totalStaked[i] += amountOuts[i];
        }
        uint256 price = getPriceFromChainlink();
        uint256 usdAmount = amount * price / 1 ether;

        user.usdAmount += usdAmount;
        emit TokenZappedIn(msg.sender, amount, _percents, amountOuts, usdAmount, brewsFee + deployerFee);

        if (totalPercentage < FEE_DENOMINATOR) {
            payable(msg.sender).transfer(ethAmount * (FEE_DENOMINATOR - totalPercentage) / FEE_DENOMINATOR);
        }
    }

    function _beforeZapIn(address _token, uint256 _amount) internal returns (uint256 amount) {
        if (_token == address(0x0)) return msg.value;

        uint8 allowedMethod = IBrewlabsIndexFactory(factory).allowedTokens(_token);
        require(allowedMethod > 0, "Cannot zap in with unsupported token");
        require(_amount > 1000, "Not enough amount");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        address[] memory _path = new address[](2);
        _path[0] = _token;
        _path[1] = WBNB;

        amount = _safeSwapForETH(_amount, _path);
    }

    /**
     * @notice Claim tokens from contract.
     *         If the user exits the index in a loss then there is no fee.
     *         If the user exists the index in a profit, processing fee will be applied.
     */
    function claimTokens(uint256 _percent) external onlyInitialized nonReentrant {
        require(_percent > 0 && _percent <= FEE_DENOMINATOR, "Invalid percent");
        UserInfo storage user = users[msg.sender];
        require(user.usdAmount > 0, "No available tokens");

        uint256 _fee = totalFee();
        uint256 discount = _getDiscount(msg.sender);
        uint256 price = getPriceFromChainlink();
        uint256 expectedAmt = _expectedEth(user.amounts);

        bool bCommission = (expectedAmt * price / 1 ether) > user.usdAmount;
        uint256 profit = bCommission ? ((expectedAmt * price / 1 ether) - user.usdAmount) : 0;

        uint256[] memory amounts = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            uint256 claimAmount = (user.amounts[i] * _percent) / FEE_DENOMINATOR;
            amounts[i] = claimAmount;

            uint256 claimFee = 0;
            if (bCommission) {
                claimFee = (claimAmount * profit * _fee * discount) / user.usdAmount / FEE_DENOMINATOR ** 2;
                if (commissionWallet == address(0x0)) {
                    pendingCommissions[i] += claimFee;
                } else {
                    _transferToken(tokens[i], commissionWallet, claimFee);
                }
            }
            _transferToken(tokens[i], msg.sender, claimAmount - claimFee);

            user.amounts[i] -= claimAmount;
            totalStaked[i] -= claimAmount;
        }

        uint256 commission = 0;
        if (bCommission) {
            commission = (expectedAmt * _percent * profit) / FEE_DENOMINATOR;
            commission = (commission * _fee * discount) / user.usdAmount / FEE_DENOMINATOR ** 2;
        }
        totalCommissions += commission * price / 1 ether;

        uint256 claimedUsdAmount = (user.usdAmount * _percent) / FEE_DENOMINATOR;
        user.usdAmount -= claimedUsdAmount;
        emit TokenClaimed(msg.sender, amounts, claimedUsdAmount, commission);
    }

    /**
     * @notice Sale tokens from contract and claim ETH.
     *         If the user exits the index in a loss then there is no fee.
     *         If the user exists the index in a profit, processing fee will be applied.
     */
    function zapOut(address _token) external onlyInitialized nonReentrant {
        UserInfo storage user = users[msg.sender];
        require(user.usdAmount > 0, "No available tokens");

        uint256 ethAmount;
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            uint256 claimAmount = user.amounts[i];
            totalStaked[i] -= claimAmount;

            uint256 amountOut;
            if (address(tokens[i]) == WBNB) {
                amountOut = claimAmount;
                IWETH(WBNB).withdraw(amountOut);
            } else {
                amountOut = _safeSwapForETH(claimAmount, getSwapPath(i, false));
            }
            ethAmount += amountOut;
        }

        uint256 commission = 0;
        uint256 _fee = totalFee();
        uint256 discount = _getDiscount(msg.sender);
        uint256 price = getPriceFromChainlink();
        if ((ethAmount * price / 1 ether) > user.usdAmount) {
            uint256 profit = ((ethAmount * price / 1 ether) - user.usdAmount) * 1e18 / price;
            commission = (profit * _fee * discount) / FEE_DENOMINATOR ** 2;
            if (commissionWallet == address(0x0)) {
                pendingCommissions[NUM_TOKENS] += commission;
            } else {
                payable(commissionWallet).transfer(commission);
            }

            ethAmount -= commission;
        }
        totalCommissions += commission * price / 1 ether;

        emit TokenZappedOut(msg.sender, user.amounts, ethAmount, commission);
        delete users[msg.sender];

        _afterZapOut(_token, msg.sender, ethAmount);
    }

    function _afterZapOut(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0x0)) {
            payable(_to).transfer(_amount);
            return;
        }

        uint8 allowedMethod = IBrewlabsIndexFactory(factory).allowedTokens(_token);
        require(allowedMethod > 0, "Cannot zap out with this token");

        address[] memory _path = new address[](2);
        _path[0] = WBNB;
        _path[1] = _token;
        _safeSwapEth(_amount, _path, _to);
    }

    /**
     * @notice Once the user purchases the tokens through the contract, the user can then choose to at anytime
     *  to mint an NFT that would represent the ownership of their tokens in the contract.
     * The purpose of this is to allow users to mint an NFT that represents their value in the index and at their discretion,
     *  transfer or sell that NFT to another wallet.
     */
    function mintNft() external payable onlyInitialized nonReentrant returns (uint256) {
        UserInfo storage user = users[msg.sender];
        require(user.usdAmount > 0, "No available tokens");

        _transferPerformanceFee();

        // mint NFT
        uint256 tokenId = IBrewlabsIndexNft(address(indexNft)).mint(msg.sender);

        // lock available tokens for NFT
        NftInfo storage nftData = nfts[tokenId];
        nftData.amounts = user.amounts;
        nftData.usdAmount = user.usdAmount;

        nftData.level = 1;
        if (nftData.usdAmount < 1000 ether) nftData.level = 0;
        if (nftData.usdAmount > 5000 ether) nftData.level = 2;

        delete users[msg.sender];
        emit TokenLocked(msg.sender, nftData.amounts, nftData.usdAmount, tokenId);

        return tokenId;
    }

    /**
     * @notice Stake the NFT back into the index to claim/zap out their tokens.
     */
    function stakeNft(uint256 tokenId) external payable onlyInitialized nonReentrant {
        UserInfo storage user = users[msg.sender];

        _transferPerformanceFee();

        // burn NFT
        indexNft.safeTransferFrom(msg.sender, address(this), tokenId);
        IBrewlabsIndexNft(address(indexNft)).burn(tokenId);

        NftInfo memory nftData = nfts[tokenId];
        if (user.amounts.length == 0) user.amounts = new uint256[](NUM_TOKENS);
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            user.amounts[i] += nftData.amounts[i];
        }
        user.usdAmount += nftData.usdAmount;

        emit TokenUnLocked(msg.sender, nftData.amounts, nftData.usdAmount, tokenId);
        delete nfts[tokenId];
    }

    function mintDeployerNft() external payable returns (uint256) {
        require(msg.sender == deployer, "Caller is not the deployer");
        require(deployerNftMintable, "Already Mint");

        _transferPerformanceFee();

        commissionWallet = address(0x0);
        deployerNftMintable = false;
        deployerNftId = IBrewlabsIndexNft(address(deployerNft)).mint(msg.sender);
        emit DeployerNftMinted(msg.sender, address(deployerNft), deployerNftId);
        return deployerNftId;
    }

    function stakeDeployerNft() external payable {
        commissionWallet = msg.sender;

        _transferPerformanceFee();

        deployerNft.safeTransferFrom(msg.sender, address(this), deployerNftId);
        emit DeployerNftStaked(msg.sender, deployerNftId);

        _claimPendingCommission();
    }

    function unstakeDeployerNft() external payable {
        require(msg.sender == commissionWallet, "Caller is not the commission wallet");

        commissionWallet = address(0x0);

        deployerNft.safeTransferFrom(address(this), msg.sender, deployerNftId);
        emit DeployerNftUnstaked(msg.sender, deployerNftId);
    }

    function _claimPendingCommission() internal {
        for (uint256 i = 0; i <= NUM_TOKENS; i++) {
            if (pendingCommissions[i] == 0) continue;
            if (i < NUM_TOKENS) {
                _transferToken(tokens[i], commissionWallet, pendingCommissions[i]);
            } else {
                payable(commissionWallet).transfer(pendingCommissions[i]);
            }
            pendingCommissions[i] = 0;
        }
        emit PendingCommissionClaimed(commissionWallet);
    }

    /**
     * @notice Returns purchased tokens and ETH amount at the time when bought tokens.
     * @param _user: user address
     */
    function userInfo(address _user) external view returns (uint256[] memory amounts, uint256 usdAmount) {
        UserInfo memory _userData = users[_user];
        usdAmount = _userData.usdAmount;
        amounts = new uint256[](NUM_TOKENS);
        if (usdAmount == 0) return (amounts, usdAmount);

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
        returns (uint256 level, uint256[] memory amounts, uint256 usdAmount)
    {
        NftInfo memory _nftData = nfts[_tokenId];
        level = _nftData.level;
        usdAmount = _nftData.usdAmount;
        amounts = new uint256[](NUM_TOKENS);
        if (usdAmount == 0) return (1, amounts, usdAmount);

        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            amounts[i] = _nftData.amounts[i];
        }
    }

    function getPendingCommissions() external view returns (uint256[] memory) {
        return pendingCommissions;
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
    function getSwapPath(uint256 _index, bool _isZapIn) public view returns (address[] memory) {
        if (_isZapIn) return ethToTokenPaths[_index];

        uint256 len = ethToTokenPaths[_index].length;
        address[] memory _path = new address[](len);
        for (uint8 j = 0; j < len; j++) {
            _path[j] = ethToTokenPaths[_index][len - j - 1];
        }

        return _path;
    }

    function getPriceFromChainlink() public view returns (uint256) {
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

    function totalFee() public view returns (uint256) {
        return IBrewlabsIndexFactory(factory).brewlabsFee() + fee;
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
    function setFee(uint256 _fee) external {
        require(msg.sender == deployer || msg.sender == owner(), "Caller is not the deployer or owner");
        require(_fee <= IBrewlabsIndexFactory(factory).feeLimit(), "Cannot exceed fee limit of factory");

        fee = _fee;
        emit SetDeployerFee(_fee);
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

        emit ServiceInfoChanged(_addr, _fee);
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

    function _transferToken(IERC20 _token, address _to, uint256 _amount) internal {
        if (address(_token) == WBNB) {
            IWETH(WBNB).withdraw(_amount);
            payable(_to).transfer(_amount);
        } else {
            _token.safeTransfer(_to, _amount);
        }
    }

    /**
     * @notice Returns the expected eth amount by swapping provided tokens.
     * @param amounts: amounts to swap
     */
    function _expectedEth(uint256[] memory amounts) internal view returns (uint256 amountOut) {
        amountOut = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            if (amounts[i] == 0) continue;

            if (address(tokens[i]) == WBNB) {
                amountOut += amounts[i];
            } else {
                uint256[] memory _amounts = IUniRouter02(swapRouter).getAmountsOut(amounts[i], getSwapPath(i, false));
                amountOut += _amounts[_amounts.length - 1];
            }
        }
    }

    function _getDiscount(address _user) internal view returns (uint256) {
        address discountMgr = IBrewlabsIndexFactory(factory).discountMgr();
        if (discountMgr == address(0x0)) return FEE_DENOMINATOR;

        return FEE_DENOMINATOR - IBrewlabsDiscountMgr(discountMgr).discountOf(_user);
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

    /**
     * onERC721Received(address operator, address from, uint256 tokenId, bytes data) → bytes4
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data)
        public
        override
        returns (bytes4)
    {
        require(msg.sender == address(indexNft) || msg.sender == address(deployerNft), "not enabled NFT");
        return super.onERC721Received(operator, from, tokenId, data);
    }

    receive() external payable {}
}
