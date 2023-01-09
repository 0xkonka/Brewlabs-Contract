// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libs/IUniRouter02.sol";

contract BrewlabsIndexes is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool public isInitialized;
    uint8 public constant NUM_TOKENS = 2;

    IERC721 public nft;
    IERC20[NUM_TOKENS] public tokens;

    address public swapRouter;
    address[NUM_TOKENS][] public ethToTokenPaths;
    address[NUM_TOKENS][] public tokenToEthPaths;

    struct UserInfo {
        uint256[NUM_TOKENS] amounts;
        uint256 zappedEthAmount;
    }

    mapping(address => UserInfo) public users;

    struct NftInfo {
        uint256[NUM_TOKENS] amounts;
        uint256 zappedEthAmount;
    }

    mapping(uint256 => NftInfo) public nfts;

    uint8 public fee;
    address public treasury = 0x408c4aDa67aE1244dfeC7D609dea3c232843189A;
    uint256 public performanceFee = 0.0035 ether;

    constructor() {}

    function initialize(IERC20[NUM_TOKENS] memory _tokens, IERC721 _nft, address[NUM_TOKENS][] memory _paths) external onlyOwner {
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        nft = _nft;
        tokens = _tokens;
        ethToTokenPaths = _paths;
        tokenToEthPaths = _paths;

        for(uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256 len = _paths[i].length;
            for(uint8 j = 0; j < len / 2; j++) {
                address t = tokenToEthPaths[i][j];
                tokenToEthPaths[i][j] = tokenToEthPaths[i][len - j - 1];
                tokenToEthPaths[i][len - j - 1] = t;
            }
        }
        isInitialized = true;
    }

    function userInfo(address _user) external view returns (UserInfo memory) {
        return users[_user];
    }

    function nftInfo(uint256 _tokenId) external view returns (NftInfo memory) {
        return nfts[_tokenId];
    }

    function _getSwapPath(uint8 _type, uint8 _index) public view returns (address[] memory) {
        uint256 len = ethToTokenPaths[_index].length;
        address[] memory  _path = new address[](len);
        for(uint8 j = 0; j < len; j++) {
            if(_type == 0) {
                _path[j] = ethToTokenPaths[_index][j];
            } else {
                _path[j] = ethToTokenPaths[_index][len - j - 1];
            }
        }

        return _path;
    }

    function _expectedEth(uint256[] memory amounts) internal view returns(uint256 amountOut) {
        amountOut = 0;        
        for(uint8 i = 0; i < NUM_TOKENS; i++) {
            uint256[] memory _amounts = IUniRouter02(swapRouter).getAmountsOut(amounts[i], _getSwapPath(1, i));
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
        // uint256[] memory amounts = IUniRouter02(swapRouter).getAmountsOut(_amountIn, _path);
        // uint256 amountOut = amounts[amounts.length - 1];

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
        // uint256[] memory amounts = IUniRouter02(swapRouter).getAmountsOut(_amountIn, _path);
        // uint256 amountOut = amounts[amounts.length - 1];

        IERC20(_path[0]).safeApprove(swapRouter, _amountIn);

        uint256 beforeAmt = address(this).balance;
        IUniRouter02(swapRouter).swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amountIn, 0, _path, address(this), block.timestamp + 600
        );

        return address(this).balance - beforeAmt;
    }

    receive() external payable {}
}
