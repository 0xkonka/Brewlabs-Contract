// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libs/PriceOracle.sol";
import "./libs/AggregatorV3Interface.sol";

interface IERC20Extended is IERC20 {
    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);
}

interface ITwapOracle {
    function twap(address _token, uint256 _amountIn) external view returns (uint144 _amountOut);
}

contract BrewlabsPriceOracle is PriceOracle {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Extended;

    address public admin;
    address public wrapped;

    /// @notice Chainlink Aggregators
    mapping(address => AggregatorV3Interface) public aggregators;

    struct PriceInfo {
        address token; // Address of token contract, TOKEN
        address baseToken; // Address of base token contract, BASETOKEN
        address lpToken; // Address of TOKEN-BASETOKEN pair contract
        bool active; // Active status of price record 0
    }

    struct TwapPriceInfo {
        address token; // Address of token contract, TOKEN
        address baseToken; // Address of base token contract, BASETOKEN
        address twapOracle; // Address of twap oracle contract
        bool active; // Active status of price record 0
    }

    mapping(address => PriceInfo) public priceRecords;
    mapping(address => TwapPriceInfo) public priceTwapRecords;
    mapping(address => uint256) public assetPrices;

    event NewAdmin(address oldAdmin, address newAdmin);
    event PriceRecordUpdated(address token, address baseToken, address lpToken, bool _active);
    event TwapPriceRecordUpdated(address token, address baseToken, address twapOracle, bool _active);
    event DirectPriceUpdated(address token, uint256 oldPrice, uint256 newPrice);
    event AggregatorUpdated(address tokenAddress, address source);

    constructor(address _wrapped) {
        wrapped = _wrapped;
        admin = msg.sender;
    }

    function getTokenPrice(address _tokenAddress) external view override returns (uint256) {
        address tokenAddress = _tokenAddress;
        if (_tokenAddress == address(0)) {
            tokenAddress = wrapped;
        }
        uint256 tokenPrice = assetPrices[tokenAddress];
        if (tokenPrice == 0) {
            tokenPrice = getPriceFromOracle(tokenAddress);
        }
        if (tokenPrice == 0) {
            tokenPrice = getPriceFromTwap(tokenAddress);
        }
        if (tokenPrice == 0) {
            tokenPrice = getPriceFromDex(tokenAddress);
        }
        return tokenPrice;
    }

    function getPriceFromDex(address _tokenAddress) public view returns (uint256) {
        PriceInfo storage priceInfo = priceRecords[_tokenAddress];
        if (priceInfo.active) {
            uint256 rawTokenAmount = IERC20Extended(priceInfo.token).balanceOf(priceInfo.lpToken);
            uint256 tokenDecimalDelta = 18 - uint256(IERC20Extended(priceInfo.token).decimals());
            uint256 tokenAmount = rawTokenAmount.mul(10 ** tokenDecimalDelta);
            uint256 rawBaseTokenAmount = IERC20Extended(priceInfo.baseToken).balanceOf(priceInfo.lpToken);
            uint256 baseTokenDecimalDelta = 18 - uint256(IERC20Extended(priceInfo.baseToken).decimals());
            uint256 baseTokenAmount = rawBaseTokenAmount.mul(10 ** baseTokenDecimalDelta);
            uint256 baseTokenPrice = getPriceFromOracle(priceInfo.baseToken);
            uint256 tokenPrice = baseTokenPrice.mul(baseTokenAmount).div(tokenAmount);

            return tokenPrice;
        } else {
            return 0;
        }
    }

    function getPriceFromTwap(address _tokenAddress) public view returns (uint256) {
        TwapPriceInfo storage priceInfo = priceTwapRecords[_tokenAddress];
        if (priceInfo.active) {
            uint144 twapPrice = ITwapOracle(priceInfo.twapOracle).twap(
                priceInfo.token, 10 ** (uint256(IERC20Extended(priceInfo.token).decimals()))
            );
            uint256 baseTokenPrice = getPriceFromOracle(priceInfo.baseToken);
            uint256 tokenPrice =
                baseTokenPrice.mul(twapPrice).div(10 ** (uint256(IERC20Extended(priceInfo.token).decimals())));
            return tokenPrice;
        } else {
            return 0;
        }
    }

    function getPriceFromOracle(address _tokenAddress) public view returns (uint256) {
        uint256 chainLinkPrice = getPriceFromChainlink(_tokenAddress);
        return chainLinkPrice;
    }

    function getPriceFromChainlink(address _tokenAddress) public view returns (uint256) {
        AggregatorV3Interface aggregator = aggregators[_tokenAddress];
        if (address(aggregator) != address(0)) {
            (, int256 answer,,,) = aggregator.latestRoundData();

            // It's fine for price to be 0. We have two price feeds.
            if (answer == 0) {
                return 0;
            }

            // Extend the decimals to 1e18.
            uint256 retVal = uint256(answer);
            uint256 price = retVal.mul(10 ** (18 - uint256(aggregator.decimals())));

            return price;
        }
        return 0;
    }

    function setDexPriceInfo(address _token, address _baseToken, address _lpToken, bool _active) external {
        require(msg.sender == admin, "only admin can set DEX price");
        PriceInfo storage priceInfo = priceRecords[_token];
        uint256 baseTokenPrice = getPriceFromOracle(_baseToken);
        require(baseTokenPrice > 0, "invalid base token");
        priceInfo.token = _token;
        priceInfo.baseToken = _baseToken;
        priceInfo.lpToken = _lpToken;
        priceInfo.active = _active;
        emit PriceRecordUpdated(_token, _baseToken, _lpToken, _active);
    }

    function setTwapPriceInfo(address _token, address _baseToken, address _twapOracle, bool _active) external {
        require(msg.sender == admin, "only admin can set DEX price");
        TwapPriceInfo storage priceInfo = priceTwapRecords[_token];
        uint256 baseTokenPrice = getPriceFromOracle(_baseToken);
        require(baseTokenPrice > 0, "invalid base token");
        priceInfo.token = _token;
        priceInfo.baseToken = _baseToken;
        priceInfo.twapOracle = _twapOracle;
        priceInfo.active = _active;
        emit TwapPriceRecordUpdated(_token, _baseToken, _twapOracle, _active);
    }

    function setDirectPrice(address _token, uint256 _price) external {
        require(msg.sender == admin, "only admin can set direct price");
        emit DirectPriceUpdated(_token, assetPrices[_token], _price);
        assetPrices[_token] = _price;
    }

    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "only admin can set new admin");
        address oldAdmin = admin;
        admin = newAdmin;

        emit NewAdmin(oldAdmin, newAdmin);
    }

    function setAggregators(address[] calldata tokenAddresses, address[] calldata sources) external {
        require(msg.sender == admin, "only the admin may set the aggregators");
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            aggregators[tokenAddresses[i]] = AggregatorV3Interface(sources[i]);
            emit AggregatorUpdated(tokenAddresses[i], sources[i]);
        }
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
