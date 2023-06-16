// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {AggregatorV3Interface} from "../libs/AggregatorV3Interface.sol";
import {IBrewlabsAggregator} from "../libs/IBrewlabsAggregator.sol";
import {IWETH} from "../libs/IWETH.sol";
import {IWrapper} from "../libs/IWrapper.sol";

interface IBrewlabsIndexFactory {
    function brewlabsFee() external view returns (uint256);
    function feeLimits(uint256 index) external view returns (uint256);
    function brewlabsWallet() external view returns (address);
    function discountMgr() external view returns (address);
    function allowedTokens(address token) external view returns (uint8);
    function wrappers(address token) external view returns (address);
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
    address public WNATIVE;

    string public name;

    IBrewlabsIndexFactory public factory;
    IERC721 public indexNft;
    IERC721 public deployerNft;

    uint256 public NUM_TOKENS;
    IERC20[] public tokens;

    IBrewlabsAggregator public swapAggregator;

    // Info of each user.
    struct UserInfo {
        uint256[] amounts; // How many tokens that user has bought
        uint256 usdAmount; // USD amount that user sold
    }

    mapping(address => UserInfo) private users;

    struct NftInfo {
        uint256 level;
        uint256[] amounts; // locked token amounts in NFT
        uint256 usdAmount; // USD amount that sold for above tokens
    }

    mapping(uint256 => NftInfo) private nfts;
    uint256[] public totalStaked;

    uint256 public depositFee;
    uint256 public commissionFee;
    uint256 public performanceFee;
    address public treasury;
    address public deployer;
    address public commissionWallet;

    uint256 public totalCommissions;
    uint256[] private pendingCommissions;

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
    event CommissionClaimed(address indexed user);

    event SetIndexNft(address newNftAddr);
    event SetDeployerNft(address newNftAddr);
    event SetFees(uint256 fee0, uint256 fee1);
    event SetFeeWallet(address wallet);
    event SetSwapAggregator(address aggregator);
    event ServiceInfoChanged(address addr, uint256 fee);

    modifier onlyInitialized() {
        require(isInitialized, "Not initialized");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize index contract.
     * @param _name: index name
     * @param _tokens: token list that user can buy in a transaction
     * @param _indexNft: Index NFT address
     * @param _deployerNft: Deployer NFT address
     * @param _fees: additional fee for deployer
     * @param _owner: index owner address
     * @param _deployer: index deployer address
     * @param _commissionWallet: index commission wallet
     */
    function initialize(
        string memory _name,
        address _aggregator,
        IERC20[] memory _tokens,
        IERC721 _indexNft,
        IERC721 _deployerNft,
        uint256[2] memory _fees,
        address _owner,
        address _deployer,
        address _commissionWallet
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");
        require(_tokens.length <= 5, "Exceed maximum tokens");

        isInitialized = true;

        name = _name;

        // initialize default variables
        FEE_DENOMINATOR = 10000;
        PRICE_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; // BNB-USD FEED
        swapAggregator = IBrewlabsAggregator(_aggregator);
        WNATIVE = swapAggregator.WNATIVE();
        NUM_TOKENS = _tokens.length;

        depositFee = _fees[0];
        commissionFee = _fees[1];
        performanceFee = 0.01 ether;
        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        deployer = _deployer;
        commissionWallet = _commissionWallet;

        factory = IBrewlabsIndexFactory(msg.sender);

        indexNft = _indexNft;
        deployerNft = _deployerNft;
        tokens = _tokens;

        totalStaked = new uint256[](NUM_TOKENS);

        pendingCommissions = new uint256[](NUM_TOKENS + 1);

        _transferOwnership(_owner);
    }

    function precomputeZapIn(address _token, uint256 _amount, uint256[] memory _percents)
        external
        view
        returns (IBrewlabsAggregator.FormattedOffer[] memory queries)
    {
        queries = new IBrewlabsAggregator.FormattedOffer[](NUM_TOKENS + 1);
        uint256 ethAmount = _amount;
        if (_token != address(0x0)) {
            queries[0] = swapAggregator.findBestPath(_amount, _token, WNATIVE, 3);
            ethAmount = queries[0].amounts[queries[0].amounts.length - 1];
        }

        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountIn;
            if (i < _percents.length) {
                amountIn = (ethAmount * _percents[i]) / FEE_DENOMINATOR;
            }
            if (amountIn == 0 || address(tokens[i]) == WNATIVE) continue;

            queries[i + 1] = swapAggregator.findBestPath(amountIn, WNATIVE, address(tokens[i]), 3);
        }
    }

    /**
     * @notice Buy tokens by paying ETH and lock tokens in contract.
     *         When buy tokens, should pay processing fee(brewlabs fixed fee + deployer fee).
     * @param _percents: list of ETH allocation points to buy tokens
     */
    function zapIn(
        address _token,
        uint256 _amount,
        uint256[] memory _percents,
        IBrewlabsAggregator.Trade[] memory _trades
    ) external payable onlyInitialized nonReentrant {
        require(_percents.length == NUM_TOKENS, "Invalid percents");
        require(_trades.length == NUM_TOKENS + 1, "Invalid trade config");

        uint256 totalPercentage = 0;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            totalPercentage += _percents[i];
        }
        require(totalPercentage <= FEE_DENOMINATOR, "Total percentage cannot exceed 10000");

        uint256 ethAmount = _beforeZapIn(_token, _amount, _trades[0]);

        uint256 price = getPriceFromChainlink();
        uint256 discount = _getDiscount(msg.sender);

        // pay brewlabs fee
        uint256 brewsFee = (ethAmount * factory.brewlabsFee() * discount) / FEE_DENOMINATOR ** 2;
        payable(factory.brewlabsWallet()).transfer(brewsFee);
        // pay deployer fee
        uint256 deployerFee = (ethAmount * depositFee * discount) / FEE_DENOMINATOR ** 2;
        if (commissionWallet == address(0x0)) {
            pendingCommissions[NUM_TOKENS] += deployerFee;
            totalCommissions += deployerFee * price / 1 ether;
        } else {
            payable(commissionWallet).transfer(deployerFee);
        }
        ethAmount -= brewsFee + deployerFee;

        UserInfo storage user = users[msg.sender];
        if (user.usdAmount == 0) {
            user.amounts = new uint256[](NUM_TOKENS);
        }

        // buy tokens
        uint256 amount;
        uint256[] memory amountOuts = new uint256[](NUM_TOKENS);
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 amountIn = (ethAmount * _percents[i]) / FEE_DENOMINATOR;
            if (amountIn == 0) continue;

            if (address(tokens[i]) == WNATIVE) {
                IWETH(WNATIVE).deposit{value: amountIn}();
                amountOuts[i] = amountIn;
            } else {
                amountOuts[i] = _safeSwapEth(amountIn, address(tokens[i]), address(this), _trades[i + 1]);
            }

            user.amounts[i] += amountOuts[i];
            totalStaked[i] += amountOuts[i];

            amount += amountIn;
        }
        uint256 usdAmount = amount * price / 1 ether;

        user.usdAmount += usdAmount;
        emit TokenZappedIn(msg.sender, amount, _percents, amountOuts, usdAmount, brewsFee + deployerFee);

        if (totalPercentage < FEE_DENOMINATOR) {
            payable(msg.sender).transfer(ethAmount - amount);
        }
    }

    function _beforeZapIn(address _token, uint256 _amount, IBrewlabsAggregator.Trade memory _trade)
        internal
        returns (uint256 amount)
    {
        if (_token == address(0x0)) return msg.value;

        uint8 allowedMethod = factory.allowedTokens(_token);
        require(allowedMethod > 0, "Cannot zap in with unsupported token");
        require(_amount > 1000, "Not enough amount");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        if (allowedMethod == 1) {
            amount = _safeSwapForETH(_amount, _token, _trade);
        } else {
            amount = _amount;

            address wrapper = factory.wrappers(_token);
            if (_token == WNATIVE) {
                IWETH(WNATIVE).withdraw(_amount);
            } else {
                IERC20(_token).approve(wrapper, _amount);
                amount = IWrapper(wrapper).withdraw(_amount);
            }
        }
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

        uint256 discount = _getDiscount(msg.sender);
        uint256 price = getPriceFromChainlink();
        uint256 expectedAmt = _expectedEth(user.amounts);

        bool bCommission = (expectedAmt * price / 1 ether) > user.usdAmount;
        uint256 profit = bCommission ? ((expectedAmt * price / 1 ether) - user.usdAmount) : 0;

        address _brewsWallet = factory.brewlabsWallet();
        uint256 _brewsFee = factory.brewlabsFee();

        uint256[] memory amounts = new uint256[](NUM_TOKENS);
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            uint256 claimAmount = (user.amounts[i] * _percent) / FEE_DENOMINATOR;
            amounts[i] = claimAmount;

            uint256 claimFee = 0;
            uint256 brewsFee = 0;
            if (bCommission) {
                brewsFee = (claimAmount * profit * _brewsFee * discount) / user.usdAmount / FEE_DENOMINATOR ** 2;
                _transferToken(tokens[i], _brewsWallet, brewsFee);

                claimFee = (claimAmount * profit * commissionFee * discount) / user.usdAmount / FEE_DENOMINATOR ** 2;
                if (commissionWallet == address(0x0)) {
                    pendingCommissions[i] += claimFee;
                } else {
                    _transferToken(tokens[i], commissionWallet, claimFee);
                }
            }
            _transferToken(tokens[i], msg.sender, claimAmount - claimFee - brewsFee);

            user.amounts[i] -= claimAmount;
            totalStaked[i] -= claimAmount;
        }

        uint256 commission = 0;
        if (bCommission) {
            commission = (expectedAmt * _percent * profit) / FEE_DENOMINATOR;
            commission = (commission * commissionFee * discount) / user.usdAmount / FEE_DENOMINATOR ** 2;

            if (commissionWallet == address(0x0)) {
                totalCommissions += commission * price / 1 ether;
            }
        }

        uint256 claimedUsdAmount = (user.usdAmount * _percent) / FEE_DENOMINATOR;
        user.usdAmount -= claimedUsdAmount;
        emit TokenClaimed(msg.sender, amounts, claimedUsdAmount, commission);
    }

    function precomputeZapOut(address _token)
        external
        view
        returns (IBrewlabsAggregator.FormattedOffer[] memory queries)
    {
        queries = new IBrewlabsAggregator.FormattedOffer[](NUM_TOKENS + 1);

        uint256 ethAmount = 0;
        UserInfo memory user = users[msg.sender];
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            if (user.amounts[i] == 0) continue;
            if (address(tokens[i]) == WNATIVE) {
                ethAmount += user.amounts[i];
                continue;
            }

            queries[i] = swapAggregator.findBestPath(user.amounts[i], address(tokens[i]), WNATIVE, 3);
            ethAmount += queries[i].amounts[queries[i].amounts.length - 1];
        }

        if (_token != address(0x0)) {
            queries[NUM_TOKENS] = swapAggregator.findBestPath(ethAmount, WNATIVE, _token, 3);
        }
    }

    /**
     * @notice Sale tokens from contract and claim ETH.
     *         If the user exits the index in a loss then there is no fee.
     *         If the user exists the index in a profit, processing fee will be applied.
     */
    function zapOut(address _token, IBrewlabsAggregator.Trade[] memory _trades) external onlyInitialized nonReentrant {
        UserInfo storage user = users[msg.sender];
        require(user.usdAmount > 0, "No available tokens");
        require(_trades.length == NUM_TOKENS + 1, "Invalid trade config");

        uint256 ethAmount;
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            uint256 claimAmount = user.amounts[i];
            totalStaked[i] -= claimAmount;
            if (user.amounts[i] == 0) continue;

            uint256 amountOut;
            if (address(tokens[i]) == WNATIVE) {
                amountOut = claimAmount;
                IWETH(WNATIVE).withdraw(amountOut);
            } else {
                amountOut = _safeSwapForETH(claimAmount, address(tokens[i]), _trades[i]);
            }
            ethAmount += amountOut;
        }

        uint256 commission = 0;
        uint256 discount = _getDiscount(msg.sender);
        uint256 price = getPriceFromChainlink();
        if ((ethAmount * price / 1 ether) > user.usdAmount) {
            uint256 profit = ((ethAmount * price / 1 ether) - user.usdAmount) * 1e18 / price;

            uint256 brewsFee = (profit * factory.brewlabsFee() * discount) / FEE_DENOMINATOR ** 2;
            payable(factory.brewlabsWallet()).transfer(brewsFee);

            commission = (profit * commissionFee * discount) / FEE_DENOMINATOR ** 2;
            if (commissionWallet == address(0x0)) {
                pendingCommissions[NUM_TOKENS] += commission;
                totalCommissions += commission * price / 1 ether;
            } else {
                payable(commissionWallet).transfer(commission);
            }

            ethAmount -= commission + brewsFee;
        }
        emit TokenZappedOut(msg.sender, user.amounts, ethAmount, commission);
        delete users[msg.sender];

        _afterZapOut(_token, msg.sender, ethAmount, _trades[NUM_TOKENS]);
    }

    function _afterZapOut(address _token, address _to, uint256 _amount, IBrewlabsAggregator.Trade memory _trade)
        internal
    {
        if (_token == address(0x0)) {
            payable(_to).transfer(_amount);
            return;
        }

        uint8 allowedMethod = factory.allowedTokens(_token);
        require(allowedMethod > 0, "Cannot zap out with this token");

        if (allowedMethod == 1) {
            _safeSwapEth(_amount, _token, _to, _trade);
        } else {
            uint256 amount = _amount;
            if (_token == WNATIVE) {
                IWETH(WNATIVE).deposit{value: _amount}();
            } else {
                address wrapper = factory.wrappers(_token);
                amount = IWrapper(wrapper).deposit{value: _amount}();
            }
            IERC20(_token).safeTransfer(_to, amount);
        }
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

    function mintDeployerNft() external payable onlyInitialized nonReentrant returns (uint256) {
        require(msg.sender == deployer, "Caller is not the deployer");
        require(deployerNftId == 0, "Already Mint");

        _transferPerformanceFee();

        commissionWallet = address(0x0);
        deployerNftId = IBrewlabsIndexNft(address(deployerNft)).mint(msg.sender);
        emit DeployerNftMinted(msg.sender, address(deployerNft), deployerNftId);
        return deployerNftId;
    }

    function stakeDeployerNft() external payable onlyInitialized nonReentrant {
        commissionWallet = msg.sender;

        _transferPerformanceFee();
        _claimPendingCommission();

        deployerNft.safeTransferFrom(msg.sender, address(this), deployerNftId);
        emit DeployerNftStaked(msg.sender, deployerNftId);
    }

    function unstakeDeployerNft() external payable onlyInitialized nonReentrant {
        require(msg.sender == commissionWallet, "Caller is not operator");

        _transferPerformanceFee();

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
        totalCommissions = 0;
        emit CommissionClaimed(commissionWallet);
    }

    /**
     * @notice Returns purchased tokens and ETH amount at the time when bought tokens.
     * @param _user: user address
     */
    function userInfo(address _user) external view returns (uint256[] memory amounts, uint256 usdAmount) {
        UserInfo memory _userData = users[_user];
        if (_userData.usdAmount == 0) return (new uint256[](NUM_TOKENS), 0);
        return (_userData.amounts, _userData.usdAmount);
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
        if (_nftData.usdAmount == 0) return (1, new uint256[](NUM_TOKENS), 0);
        return (_nftData.level, _nftData.amounts, _nftData.usdAmount);
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

    /**
     * @notice Update swap aggregator.
     * @param _aggregator: swap Aggregator address
     */
    function setSwapAggregator(address _aggregator) external onlyOwner onlyInitialized {
        require(_aggregator != address(0x0), "Invalid address");
        require(IBrewlabsAggregator(_aggregator).WNATIVE() != address(0x0), "Invalid swap aggregator");

        swapAggregator = IBrewlabsAggregator(_aggregator);
        WNATIVE = IBrewlabsAggregator(_aggregator).WNATIVE();
        emit SetSwapAggregator(_aggregator);
    }

    function setIndexNft(IERC721 newNftAddr) external onlyOwner {
        require(address(newNftAddr) != address(0x0), "Invalid NFT");
        indexNft = newNftAddr;
        emit SetIndexNft(address(newNftAddr));
    }

    function setDeployerNft(IERC721 newNftAddr) external onlyOwner {
        require(deployerNftId == 0, "Deployer NFT already minted");
        require(address(newNftAddr) != address(0x0), "Invalid NFT");
        deployerNft = newNftAddr;
        emit SetDeployerNft(address(newNftAddr));
    }

    /**
     * @notice Update processing fee.
     * @param _depositfee: deposit fee in point
     * @param _commissionFee: commission fee in point
     */
    function setFees(uint256 _depositfee, uint256 _commissionFee) external payable {
        require(msg.sender == commissionWallet || msg.sender == owner(), "Caller is not the operator");
        require(
            _depositfee <= factory.feeLimits(0) && _commissionFee <= factory.feeLimits(1), "Cannot exceed fee limit of factory"
        );

        _transferPerformanceFee();

        depositFee = _depositfee;
        commissionFee = _commissionFee;
        emit SetFees(depositFee, commissionFee);
    }

    /**
     * @notice Update fee wallet.
     * @param _feeWallet: address to receive deposit/commission fee
     */
    function setFeeWallet(address _feeWallet) external payable {
        require(msg.sender == commissionWallet || msg.sender == owner(), "Caller is not the operator");
        require(_feeWallet != address(0x0), "Invalid wallet");
        
        commissionWallet = _feeWallet;
        emit SetFeeWallet(_feeWallet);
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
        if (address(_token) == WNATIVE) {
            IWETH(WNATIVE).withdraw(_amount);
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
        uint256 aggregatorFee = swapAggregator.BREWS_FEE();

        amountOut = 0;
        IBrewlabsAggregator.FormattedOffer memory query;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            if (amounts[i] == 0) continue;

            if (address(tokens[i]) == WNATIVE) {
                amountOut += amounts[i];
            } else {
                query = swapAggregator.findBestPath(amounts[i], address(tokens[i]), WNATIVE, 3);
                uint256 _amountOut = query.amounts[query.amounts.length - 1];
                if (aggregatorFee > 0) _amountOut = _amountOut * (10000 - aggregatorFee) / 10000;
                amountOut += _amountOut;
            }
        }
    }

    function _getDiscount(address _user) internal view returns (uint256) {
        address discountMgr = factory.discountMgr();
        if (discountMgr == address(0x0)) return FEE_DENOMINATOR;

        return FEE_DENOMINATOR - IBrewlabsDiscountMgr(discountMgr).discountOf(_user);
    }

    /**
     * @notice get token from ETH via swap.
     * @param _amountIn: eth amount to swap
     * @param _token: to token
     * @param _to: receiver address
     */
    function _safeSwapEth(uint256 _amountIn, address _token, address _to, IBrewlabsAggregator.Trade memory _trade)
        internal
        returns (uint256)
    {
        _trade.amountIn = _amountIn;

        uint256 beforeAmt = IERC20(_token).balanceOf(_to);
        swapAggregator.swapNoSplitFromETH{value: _amountIn}(_trade, _to);
        uint256 afterAmt = IERC20(_token).balanceOf(_to);

        return afterAmt - beforeAmt;
    }

    /**
     * @notice swap tokens to ETH.
     * @param _amountIn: token amount to swap
     * @param _token: from token
     */
    function _safeSwapForETH(uint256 _amountIn, address _token, IBrewlabsAggregator.Trade memory _trade)
        internal
        returns (uint256)
    {
        _trade.amountIn = _amountIn;

        IERC20(_token).safeApprove(address(swapAggregator), _amountIn);

        uint256 beforeAmt = address(this).balance;
        swapAggregator.swapNoSplitToETH(_trade, address(this));

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
